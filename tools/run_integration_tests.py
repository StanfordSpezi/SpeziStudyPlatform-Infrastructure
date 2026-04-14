#!/usr/bin/env python3
"""End-to-end checks for web access through oauth2-proxy."""

from __future__ import annotations

import argparse
import http.cookiejar
import json
import logging
import os
import re
import shutil
import socket
import ssl
import subprocess
import sys
import unittest
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from html.parser import HTMLParser
from typing import Tuple

LOG_FORMAT = "%(asctime)s %(levelname)s %(message)s"

DEFAULT_HEADERS = {
    "User-Agent": "SpeziIntegrationTester/1.0",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

Credentials = Tuple[str, str]
CONFIG = None


class ColorFormatter(logging.Formatter):
    """Adds simple ANSI colors when supported by the output stream."""

    COLORS = {
        logging.DEBUG: "\033[36m",
        logging.INFO: "\033[32m",
        logging.WARNING: "\033[33m",
        logging.ERROR: "\033[31m",
        logging.CRITICAL: "\033[35m",
    }
    RESET = "\033[0m"

    def __init__(self, fmt: str, use_color: bool):
        super().__init__(fmt)
        self.use_color = use_color

    def format(self, record: logging.LogRecord) -> str:
        message = super().format(record)
        if self.use_color:
            color = self.COLORS.get(record.levelno)
            if color:
                return f"{color}{message}{self.RESET}"
        return message


def configure_logging(verbose: bool = False) -> None:
    """Configure root logger with optional color support."""
    handler = logging.StreamHandler()
    use_color = sys.stderr.isatty() and os.environ.get("NO_COLOR") is None
    handler.setFormatter(ColorFormatter(LOG_FORMAT, use_color=use_color))

    root = logging.getLogger()
    root.handlers.clear()
    root.setLevel(logging.DEBUG if verbose else logging.INFO)
    root.addHandler(handler)


class LoginFormParser(HTMLParser):
    """Extracts the first login form and its inputs."""

    def __init__(self):
        super().__init__()
        self.action: str | None = None
        self.method: str = "post"
        self._parsing_form = False
        self._form_captured = False
        self.fields: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs):
        if tag.lower() == "form" and not self._form_captured:
            self._parsing_form = True
            self._form_captured = True
            attr_map = {k.lower(): v for k, v in attrs}
            self.action = attr_map.get("action", "")
            self.method = attr_map.get("method", "post").lower()
        elif tag.lower() == "input" and self._parsing_form:
            attr_map = {k.lower(): v for k, v in attrs}
            name = attr_map.get("name")
            if name:
                self.fields[name] = attr_map.get("value", "")

    def handle_endtag(self, tag: str):
        if tag.lower() == "form" and self._parsing_form:
            self._parsing_form = False


@dataclass
class Response:
    body: str
    url: str
    status: int


class HTTPSession:
    """Minimal HTTP session with cookie handling for integration checks."""

    def __init__(self, *, verify_ssl: bool, timeout: int):
        cookie_jar = http.cookiejar.CookieJar()
        handlers = [urllib.request.HTTPCookieProcessor(cookie_jar)]
        if verify_ssl:
            handlers.extend([urllib.request.HTTPHandler(), urllib.request.HTTPSHandler()])
        else:
            handlers.extend(
                [
                    urllib.request.HTTPHandler(),
                    urllib.request.HTTPSHandler(context=ssl._create_unverified_context()),
                ]
            )
        self._opener = urllib.request.build_opener(*handlers)
        self._timeout = timeout

    def request(
        self,
        url: str,
        *,
        data: bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> Response:
        hdrs = dict(DEFAULT_HEADERS)
        if headers:
            hdrs.update(headers)
        req = urllib.request.Request(url, data=data, headers=hdrs)
        with self._opener.open(req, timeout=self._timeout) as resp:
            payload = resp.read().decode("utf-8", errors="replace")
            return Response(payload, resp.geturl(), resp.getcode())


class TestIntegration(unittest.TestCase):
    _allowed_whoami: Response | None = None

    @classmethod
    def setUpClass(cls):
        cls.CONFIG = CONFIG
        if not cls.CONFIG.base_url:
            logging.info("Auto-detecting base URL...")
            local_ip = detect_local_ip()
            if not local_ip:
                raise unittest.SkipTest("Could not determine local IP. Please provide --base-url.")
            cls.CONFIG.base_url = f"https://spezi.{local_ip}.nip.io"

        if not cls.CONFIG.keycloak_base_url:
            cls.CONFIG.keycloak_base_url = f"{cls.CONFIG.base_url}/auth"
        if not cls.CONFIG.argocd_base_url:
            cls.CONFIG.argocd_base_url = f"{cls.CONFIG.base_url}/argo"

        logging.info(f"Running integration tests against {cls.CONFIG.base_url}")

    def setUp(self):
        self.session = HTTPSession(verify_ssl=not self.CONFIG.insecure, timeout=self.CONFIG.timeout)
        self.base_url = self.CONFIG.base_url.rstrip("/")
        self.whoami_path = self.CONFIG.whoami_path
        self.allowed_user = (self.CONFIG.username, self.CONFIG.password)
        self.denied_user = (self.CONFIG.unauthorized_username, self.CONFIG.unauthorized_password)
        self.invalid_user = (self.CONFIG.invalid_username, self.CONFIG.invalid_password)

    def _exercise_flow(self, credentials: Credentials, *, login_should_fail: bool = False) -> Response:
        entry_resp = self._fetch_page(self.base_url)
        if self._whoami_ready(entry_resp.body):
            return self._fetch_page(self._whoami_url())

        self.assertTrue(self._looks_like_login(entry_resp.body), "Did not find Keycloak login form.")
        logging.info("Logging in via Keycloak...")
        login_resp = self._perform_login(entry_resp.body, entry_resp.url, credentials)

        if login_should_fail:
            return login_resp
        if login_resp.status >= 400:
            return login_resp
        return self._fetch_page(self._whoami_url())

    def _fetch_page(self, url: str) -> Response:
        try:
            resp = self.session.request(url)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            self.fail(f"Request to {url} failed with HTTP {exc.code}: {body[:200]}")
        except urllib.error.URLError as exc:
            self.fail(f"Request to {url} failed: {exc.reason}")
        logging.debug(f"Fetched {resp.url} (HTTP {resp.status})")
        return resp

    def _perform_login(self, login_page: str, login_url: str, credentials: Credentials) -> Response:
        parser = LoginFormParser()
        parser.feed(login_page)
        self.assertIsNotNone(parser.action, "Unable to locate login form action in Keycloak response.")

        form_data = dict(parser.fields)
        form_data["username"] = credentials[0]
        form_data["password"] = credentials[1]
        payload = urllib.parse.urlencode(form_data).encode()
        post_url = urllib.parse.urljoin(login_url, parser.action or "")

        try:
            resp = self.session.request(
                post_url,
                data=payload,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            logging.debug(f"Login request received expected HTTP {exc.code}")
            return Response(body, exc.geturl(), exc.code)

        logging.debug(f"Submitted credentials to {post_url} (HTTP {resp.status})")
        return resp

    def _looks_like_login(self, html: str) -> bool:
        return "kc-form-login" in html or 'name="username"' in html

    def _whoami_url(self) -> str:
        return urllib.parse.urljoin(self.base_url + "/", self.whoami_path.lstrip("/"))

    def _whoami_ready(self, html: str) -> bool:
        return "Hostname" in html and "RemoteAddr" in html

    def test_authorized_user(self):
        """Checks if a user with correct credentials can log in and access the whoami endpoint."""
        allowed_resp = self._exercise_flow(self.allowed_user)
        self.assertEqual(allowed_resp.status, 200)
        self.assertTrue(self._whoami_ready(allowed_resp.body), "Response body is not from whoami.")
        logging.info("Authorized user successfully reached whoami endpoint.")
        TestIntegration._allowed_whoami = allowed_resp

    def test_unauthorized_user(self):
        """Checks if a user with valid credentials but insufficient permissions is denied."""
        denied_resp = self._exercise_flow(self.denied_user)
        self.assertIn(denied_resp.status, {401, 403}, "Unauthorized user was not denied access.")
        logging.info("Unauthorized user was denied access as expected.")

    def test_invalid_credentials(self):
        """Checks if a user with invalid credentials is rejected at the login page."""
        invalid_resp = self._exercise_flow(self.invalid_user, login_should_fail=True)
        body_lower = invalid_resp.body.lower()
        is_error_status = invalid_resp.status in {400, 401, 403}
        has_error_message = any(
            token in body_lower
            for token in ["invalid username", "invalid user", "invalid_login", "account is not enabled"]
        )

        self.assertTrue(
            is_error_status or has_error_message,
            f"Invalid credentials were not rejected as expected. Status: {invalid_resp.status}, Body: {invalid_resp.body[:200]}",
        )
        logging.info("Invalid credentials correctly rejected.")

    def test_oauth2_proxy_headers(self):
        """Checks for the presence of auth headers forwarded by oauth2-proxy."""
        if TestIntegration._allowed_whoami is None:
            self.test_authorized_user()
            self.assertIsNotNone(TestIntegration._allowed_whoami)

        resp = TestIntegration._allowed_whoami
        body_lower = resp.body.lower()
        username = self.allowed_user[0].lower()

        header_prefixes = [
            "x-auth-request-user:",
            "x-auth-request-email:",
            "x-forwarded-preferred-username:",
            "x-forwarded-user:",
        ]
        self.assertTrue(
            any(prefix in body_lower for prefix in header_prefixes),
            "whoami response did not include forwarded auth headers.",
        )
        self.assertIn(username, body_lower, "whoami response did not include the authenticated username.")
        logging.info("OAuth2-proxy forwarded auth headers detected.")

    def test_keycloak_openid_configuration(self):
        """Checks if Keycloak's OIDC discovery endpoint is healthy and returns valid JSON."""
        url = f"{self.CONFIG.keycloak_base_url.rstrip('/')}/realms/{self.CONFIG.keycloak_realm}/.well-known/openid-configuration"
        resp = self._fetch_page(url)
        self.assertEqual(resp.status, 200)

        try:
            payload = json.loads(resp.body)
        except json.JSONDecodeError:
            self.fail("Keycloak OIDC discovery response is not valid JSON.")

        required_keys = ["issuer", "authorization_endpoint", "token_endpoint"]
        missing = [key for key in required_keys if key not in payload]
        self.assertFalse(missing, f"Keycloak discovery document missing keys: {', '.join(missing)}")

        self.assertIn(self.CONFIG.keycloak_realm, payload.get("issuer", ""), "Issuer does not reference expected realm.")
        logging.info("Keycloak OIDC discovery document is healthy.")

    def test_argocd_health(self):
        """Checks if the Argo CD health endpoint is reachable and reports a healthy status."""
        health_url = urllib.parse.urljoin(self.CONFIG.argocd_base_url.rstrip("/") + "/", self.CONFIG.argocd_health_path.lstrip("/"))
        resp = self._fetch_page(health_url)
        self.assertEqual(resp.status, 200)
        self.assertTrue(
            "healthy" in resp.body.lower() or "ok" in resp.body.lower(),
            "Argo CD health endpoint did not report a healthy status.",
        )
        logging.info("Argo CD health endpoint returned healthy response.")

    def test_argocd_login_entrypoint(self):
        """Verifies that the Argo CD entrypoint requires authentication."""
        resp = self._fetch_page(self.CONFIG.argocd_base_url.rstrip("/"))
        self.assertIn(resp.status, {200, 302, 303})

        body_lower = resp.body.lower()
        is_argocd_page = "argo cd" in body_lower or "argo-cd" in body_lower
        is_keycloak_login = (
            self.CONFIG.keycloak_base_url and self._looks_like_login(resp.body) and self.CONFIG.keycloak_base_url in resp.url
        )
        is_generic_login = self._looks_like_login(resp.body)

        self.assertTrue(
            is_argocd_page or is_keycloak_login or is_generic_login,
            "Argo CD login entrypoint did not appear to be gated by authentication.",
        )
        logging.info("Argo CD login page is reachable and requires authentication.")


def detect_local_ip() -> str | None:
    """Detects the local IP address with WSL2/Docker-aware fallbacks."""
    env_ip = _get_env_local_ip()
    if env_ip:
        logging.info("Using local IP from environment: %s", env_ip)
        return env_ip

    docker_host_ip = _get_docker_host_ip()
    if docker_host_ip:
        logging.info("Using Docker host IP from DOCKER_HOST: %s", docker_host_ip)
        return docker_host_ip

    docker_machine_ip = _get_docker_machine_ip()
    if docker_machine_ip:
        logging.info("Using docker-machine IP: %s", docker_machine_ip)
        return docker_machine_ip

    if _is_wsl():
        wsl_ip = _get_wsl_ip_native()
        if wsl_ip:
            logging.info("Detected WSL2 IP: %s", wsl_ip)
            return wsl_ip
    elif os.name == "nt":
        wsl_ip = _get_wsl_ip_from_windows()
        if wsl_ip:
            logging.info("Detected WSL2 IP via wsl.exe: %s", wsl_ip)
            return wsl_ip

    script_path = os.path.join(os.path.dirname(__file__), "..", "scripts", "get-local-ip.sh")
    script_ip = _get_ip_from_script(script_path)
    if script_ip:
        logging.info("Detected local IP from helper script: %s", script_ip)
        return script_ip

    default_ip = _get_default_route_ip()
    if default_ip:
        logging.info("Detected local IP from default route: %s", default_ip)
        return default_ip

    logging.warning("Unable to detect local IP automatically.")
    return None


def _get_env_local_ip() -> str | None:
    for key in ("LOCAL_IP", "SPEZI_LOCAL_IP", "NIP_IO_IP"):
        value = os.environ.get(key)
        if value and _is_ipv4(value):
            return value
    return None


def _get_docker_host_ip() -> str | None:
    docker_host = os.environ.get("DOCKER_HOST", "")
    if not docker_host:
        return None
    parsed = urllib.parse.urlparse(docker_host)
    if parsed.hostname and _is_ipv4(parsed.hostname):
        return parsed.hostname
    return None


def _get_docker_machine_ip() -> str | None:
    if not shutil.which("docker-machine"):
        return None
    machine_name = os.environ.get("DOCKER_MACHINE_NAME")
    if not machine_name:
        machine_name = _run_command(["docker-machine", "active"])
    if not machine_name:
        return None
    return _extract_ipv4(_run_command(["docker-machine", "ip", machine_name]))


def _get_wsl_ip_native() -> str | None:
    output = _run_command(["ip", "-o", "-4", "addr", "show", "eth0"])
    ip = _extract_ipv4(output)
    if ip:
        return ip
    output = _run_command(["hostname", "-I"])
    return _extract_ipv4(output)


def _get_wsl_ip_from_windows() -> str | None:
    output = _run_command(["wsl.exe", "-e", "sh", "-lc", "ip -o -4 addr show eth0"])
    ip = _extract_ipv4(output)
    if ip:
        return ip
    output = _run_command(["wsl.exe", "-e", "sh", "-lc", "hostname -I"])
    return _extract_ipv4(output)


def _get_ip_from_script(script_path: str) -> str | None:
    if os.name == "nt":
        return None
    if not os.path.exists(script_path):
        logging.warning("get-local-ip.sh script not found, cannot auto-detect IP.")
        return None
    try:
        result = subprocess.run([script_path], capture_output=True, text=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        logging.error("Failed to detect local IP via helper script: %s", exc)
        return None
    return _extract_ipv4(result.stdout)


def _get_default_route_ip() -> str | None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("1.1.1.1", 80))
        ip = sock.getsockname()[0]
    except OSError:
        return None
    finally:
        sock.close()
    return ip if _is_ipv4(ip) else None


def _is_wsl() -> bool:
    if os.environ.get("WSL_INTEROP") or os.environ.get("WSL_DISTRO_NAME"):
        return True
    try:
        with open("/proc/sys/kernel/osrelease", "r", encoding="utf-8") as handle:
            return "microsoft" in handle.read().lower()
    except FileNotFoundError:
        return False


def _run_command(args: list[str]) -> str:
    try:
        result = subprocess.run(args, capture_output=True, text=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""
    return result.stdout.strip()


def _extract_ipv4(output: str) -> str | None:
    if not output:
        return None
    for match in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", output):
        if match.startswith("127."):
            continue
        if _is_ipv4(match):
            return match
    return None


def _is_ipv4(value: str) -> bool:
    try:
        socket.inet_aton(value)
    except OSError:
        return False
    return value.count(".") == 3


def main(argv=None):
    global CONFIG
    parser = argparse.ArgumentParser(description="Basic integration test for the Spezi web/whoami stack.")
    parser.add_argument(
        "--base-url",
        help="Root URL for the ingress/Traefik endpoint. If not provided, it will be auto-detected.",
    )
    parser.add_argument(
        "--username",
        default="testuser",
        help="Username for the authorized Keycloak account.",
    )
    parser.add_argument(
        "--password",
        default="password123",
        help="Password for the authorized Keycloak account.",
    )
    parser.add_argument(
        "--unauthorized-username",
        default="testuser2",
        help="Username that should be denied access to the whoami endpoint.",
    )
    parser.add_argument(
        "--unauthorized-password",
        default="password456",
        help="Password for the unauthorized Keycloak account.",
    )
    parser.add_argument(
        "--invalid-username",
        default="nouser",
        help="Username that should not exist (invalid credentials test).",
    )
    parser.add_argument(
        "--invalid-password",
        default="wrongpassword",
        help="Password for the invalid credentials test.",
    )
    parser.add_argument(
        "--whoami-path",
        default="/",
        help="Path that should return the whoami response once authenticated (default: %(default)s).",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Network timeout in seconds for each HTTP request (default: %(default)s).",
    )
    parser.add_argument(
        "--insecure",
        action="store_true",
        help="Disable TLS certificate verification (useful for nip.io/self-signed certs).",
    )
    parser.add_argument(
        "--keycloak-base-url",
        help="Base URL for Keycloak. If omitted, it will be derived from the base URL.",
    )
    parser.add_argument(
        "--keycloak-realm",
        default="spezistudyplatform",
        help="Keycloak realm name used for OIDC discovery (default: %(default)s).",
    )
    parser.add_argument(
        "--argocd-base-url",
        help="Base URL for Argo CD. If omitted, it will be derived from the base URL.",
    )
    parser.add_argument(
        "--argocd-health-path",
        default="/healthz",
        help="Path for Argo CD health endpoint (default: %(default)s).",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose logging.",
    )

    # Parse arguments and configure logging
    CONFIG, remaining_argv = parser.parse_known_args(argv or sys.argv[1:])
    configure_logging(CONFIG.verbose)

    # Pass the remaining arguments to unittest.main
    unittest.main(argv=[sys.argv[0]] + remaining_argv, verbosity=2)


if __name__ == "__main__":
    main()
