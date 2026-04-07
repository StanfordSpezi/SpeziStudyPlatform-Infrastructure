#!/usr/bin/env python3
"""Unified setup/teardown utility for local and production environments."""

from __future__ import annotations

import argparse
import base64
import json
import http.client
import logging
import os
import re
import shutil
import signal
import ssl
import subprocess
import sys
import time
import socket
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, List, Optional, Sequence, Tuple
from urllib import parse, request, error as urlerror

LOG_FORMAT = "%(asctime)s %(levelname)s %(message)s"

MODULE_DIR = Path(__file__).resolve().parent
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

try:
    from defaults import LOCAL_DEFAULTS, PROD_DEFAULTS
except ImportError as exc:  # pragma: no cover - defensive path
    raise ImportError(
        "Unable to import tools/spezi_setup/defaults.py. Ensure the file exists next to spezi_setup.py."
    ) from exc


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

    def format(self, record: logging.LogRecord) -> str:  # pragma: no cover - formatting
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



class CommandError(RuntimeError):
    """Raised when a shell command exits non-zero."""


class ShellRunner:
    """Thin wrapper around subprocess.run with logging and env overrides."""

    def __init__(self, *, cwd: Optional[Path] = None, env: Optional[dict] = None):
        self.cwd = str(cwd) if cwd else None
        self.env = env or os.environ.copy()

    def run(
        self,
        cmd: Sequence[str] | str,
        *,
        check: bool = True,
        capture_output: bool = False,
        text: bool = True,
        input: Optional[str] = None,
        extra_env: Optional[dict] = None,
        cwd: Optional[Path] = None,
    ) -> subprocess.CompletedProcess:
        if isinstance(cmd, str):
            popen_args: Sequence[str] = ["bash", "-lc", cmd]
            logging.debug("Running shell command: %s", cmd)
        else:
            popen_args = cmd
            logging.debug("Running command: %s", " ".join(cmd))

        env = self.env.copy()
        if extra_env:
            env.update(extra_env)

        try:
            result = subprocess.run(
                popen_args,
                check=False,
                capture_output=capture_output,
                text=text,
                input=input,
                env=env,
                cwd=str(cwd) if cwd else self.cwd,
            )
        except FileNotFoundError as exc:
            raise CommandError(str(exc)) from exc

        if check and result.returncode != 0:
            stdout = result.stdout.strip() if result.stdout else ""
            stderr = result.stderr.strip() if result.stderr else ""
            message = f"Command {popen_args} failed with exit code {result.returncode}"
            if stdout:
                message += f"\nstdout:\n{stdout}"
            if stderr:
                message += f"\nstderr:\n{stderr}"
            raise CommandError(message)
        return result

    def spawn(
        self,
        cmd: Sequence[str] | str,
        *,
        extra_env: Optional[dict] = None,
        cwd: Optional[Path] = None,
    ) -> subprocess.Popen:
        if isinstance(cmd, str):
            popen_args: Sequence[str] = ["bash", "-lc", cmd]
            logging.debug("Spawning shell command: %s", cmd)
        else:
            popen_args = cmd
            logging.debug("Spawning command: %s", " ".join(cmd))

        env = self.env.copy()
        if extra_env:
            env.update(extra_env)

        return subprocess.Popen(
            popen_args,
            env=env,
            cwd=str(cwd) if cwd else self.cwd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def wait_for_condition(
    description: str,
    *,
    timeout_seconds: int,
    interval: float = 1.0,
    check_fn: Callable[[], bool],
    on_timeout: Optional[Callable[[], None]] = None,
    raise_on_timeout: bool = False,
) -> bool:
    """Polls check_fn until it returns True or timeout expires."""

    deadline = time.time() + timeout_seconds
    attempt = 0
    while time.time() < deadline:
        attempt += 1
        if check_fn():
            logging.info("Condition satisfied for %s", description)
            return True
        elapsed = attempt * interval
        logging.info("Waiting for %s (elapsed %.0fs)", description, elapsed)
        time.sleep(interval)
    if on_timeout:
        on_timeout()
    if raise_on_timeout:
        raise RuntimeError(f"Timed out waiting for {description}")
    logging.warning("Timed out waiting for %s", description)
    return False


@dataclass
class WaveSpec:
    apps: Sequence[str]
    description: str
    required: bool = False


class EnvironmentSetupBase:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        # Script lives under tools/spezi_setup; assets reside at repo root.
        self.script_dir = Path(__file__).resolve().parents[2]
        self.runner = ShellRunner(cwd=self.script_dir)
        self.repo_url = "https://github.com/StanfordSpezi/spezi-study-platform-infrastructure.git"
        self.port_forward_procs: List[subprocess.Popen] = []
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGTERM, self._handle_signal)

    def _handle_signal(self, signum, _frame):  # type: ignore[override]
        logging.warning("Received signal %s, cleaning up.", signum)
        self.cleanup()
        sys.exit(1)

    def cleanup(self):
        for proc in self.port_forward_procs:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()

    def ensure_binary(self, name: str, friendly: Optional[str] = None):
        if shutil.which(name) is None:
            target = friendly or name
            raise CommandError(f"{target} is required but was not found in PATH")

    def start_port_forward(self, namespace: str, resource: str, mapping: str):
        cmd = ["kubectl", "-n", namespace, "port-forward", resource, mapping]
        proc = subprocess.Popen(
            cmd,
            env=self.runner.env,
            cwd=self.runner.cwd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.port_forward_procs.append(proc)

        local_port = mapping.split(":")[0]
        try:
            self._wait_for_local_port(int(local_port), proc, f"{namespace}/{resource}")
        except Exception:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
            raise

    def _wait_for_local_port(self, port: int, proc: subprocess.Popen, description: str, timeout: int = 15):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if proc.poll() is not None:
                stderr = ""
                if proc.stderr:
                    try:
                        stderr = proc.stderr.read().strip()
                    except Exception:
                        stderr = ""
                raise CommandError(
                    f"Port-forward for {description} exited early (code {proc.returncode}): {stderr}"
                )
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=1):
                    logging.info("Port-forward ready for %s on localhost:%s", description, port)
                    return
            except OSError:
                time.sleep(0.5)
        raise CommandError(f"Timed out waiting for port-forward {description} on localhost:{port}")

    def install_argocd(self, version: str, timeout: str):
        logging.info("Installing Argo CD (version %s)...", version)
        self.runner.run(
            "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -"
        )
        manifest_url = f"https://raw.githubusercontent.com/argoproj/argo-cd/{version}/manifests/install.yaml"
        self.runner.run(["kubectl", "apply", "-n", "argocd", "-f", manifest_url])
        cm_path = self.script_dir / "config" / "argocd" / "argocd-cm-config.yaml"
        self.runner.run(["kubectl", "apply", "-f", str(cm_path)])
        logging.info("Giving Argo CD resources a moment to settle...")
        wait_for_condition(
            "argocd pods to be scheduled",
            timeout_seconds=120,
            interval=2,
            check_fn=lambda: self.runner.run(
                ["kubectl", "get", "pods", "-n", "argocd", "--no-headers"],
                capture_output=True, check=False,
            ).stdout.strip() != "",
            raise_on_timeout=True,
        )
        self.runner.run(
            [
                "kubectl",
                "wait",
                "--for=condition=ready",
                "pod",
                "--all",
                "-n",
                "argocd",
                f"--timeout={timeout}",
            ]
        )
        logging.info("Argo CD is ready.")

    def install_tanka_plugin(self):
        logging.info("Installing Tanka CMP plugin...")
        cmp_config = self.script_dir / "config" / "argocd" / "argocd-tanka-cmp-configmap.yaml"
        patch_file = self.script_dir / "config" / "argocd" / "repo-server-patch.yaml"
        self.runner.run(["kubectl", "apply", "-f", str(cmp_config)])
        self.runner.run(
            [
                "kubectl",
                "patch",
                "deployment",
                "argocd-repo-server",
                "-n",
                "argocd",
                "--patch-file",
                str(patch_file),
            ]
        )
        self.runner.run(["kubectl", "rollout", "status", "deployment", "argocd-repo-server", "-n", "argocd"])
        logging.info("Tanka CMP plugin is configured.")

    def apply_root_application(
        self,
        app_name: str,
        source_path: str,
        tlas: Sequence[Tuple[str, str]],
    ):
        branch = self.get_git_branch()
        directory_lines = [
            "    directory:",
            "      exclude: spec.json",
        ]
        if tlas:
            directory_lines.extend([
                "      jsonnet:",
                "        tlas:",
            ])
            for name, value in tlas:
                directory_lines.append(f"        - name: {name}")
                directory_lines.append(f"          value: {json.dumps(value)}")
        else:
            directory_lines.append("      jsonnet: {}")

        lines = [
            "apiVersion: argoproj.io/v1alpha1",
            "kind: Application",
            "metadata:",
            f"  name: {app_name}",
            "  namespace: argocd",
            "spec:",
            "  project: default",
            "  source:",
            f"    repoURL: {self.repo_url}",
            f"    path: {source_path}",
            f"    targetRevision: {branch}",
        ]
        lines.extend(directory_lines)
        lines.extend([
            "  destination:",
            "    server: https://kubernetes.default.svc",
            "    namespace: argocd",
            "  syncPolicy:",
            "    automated:",
            "      prune: true",
            "      selfHeal: true",
            "    syncOptions:",
            "      - ServerSideApply=true",
        ])
        manifest = "\n".join(lines)

        self.runner.run(["kubectl", "apply", "-f", "-"], input=manifest)
        logging.info("Submitted root application %s", app_name)

    def wait_for_root_app(self, app_name: str, namespace: str = "argocd", timeout: int = 300):
        def check() -> bool:
            result = self.runner.run(
                ["kubectl", "get", "application", app_name, "-n", namespace, "-o", "json"],
                capture_output=True,
                check=False,
            )
            if result.returncode != 0 or not result.stdout:
                logging.info("Application %s not found yet", app_name)
                return False
            data = json.loads(result.stdout)
            sync = data.get("status", {}).get("sync", {}).get("status", "Waiting")
            health = data.get("status", {}).get("health", {}).get("status", "Waiting")
            logging.info("Application %s sync=%s health=%s", app_name, sync, health)
            return sync == "Synced"

        wait_for_condition(
            f"root application {app_name} to sync",
            timeout_seconds=timeout,
            interval=1,
            check_fn=check,
            raise_on_timeout=True,
        )

    def wait_for_applications(
        self,
        wave: WaveSpec,
        namespace: str = "argocd",
        timeout: int = 600,
        interval: int = 1,
    ):
        def check() -> bool:
            all_healthy = True
            for app in wave.apps:
                result = self.runner.run(
                    ["kubectl", "get", "application", app, "-n", namespace, "-o", "json"],
                    capture_output=True,
                    check=False,
                )
                if result.returncode != 0 or not result.stdout:
                    logging.info("Application %s not ready yet", app)
                    all_healthy = False
                    continue
                data = json.loads(result.stdout)
                sync = data.get("status", {}).get("sync", {}).get("status", "Unknown")
                health = data.get("status", {}).get("health", {}).get("status", "Unknown")
                logging.info("Application %s sync=%s health=%s", app, sync, health)
                if sync != "Synced" or health != "Healthy":
                    all_healthy = False
            return all_healthy

        wait_for_condition(
            wave.description,
            timeout_seconds=timeout,
            interval=interval,
            check_fn=check,
            raise_on_timeout=wave.required,
        )

    def wait_for_namespace(self, namespace: str, timeout: int = 300, interval: int = 1, required: bool = True):
        def check() -> bool:
            result = self.runner.run(["kubectl", "get", "namespace", namespace], check=False)
            return result.returncode == 0

        wait_for_condition(
            f"namespace {namespace} to exist",
            timeout_seconds=timeout,
            interval=interval,
            check_fn=check,
            raise_on_timeout=required,
        )

    def wait_for_statefulset_pod_ready(
        self,
        name: str,
        namespace: str,
        *,
        timeout: int = 600,
        interval: int = 1,
    ):
        def check() -> bool:
            result = self.runner.run([
                "kubectl",
                "-n",
                namespace,
                "get",
                "statefulset",
                name,
            ], check=False)
            if result.returncode != 0:
                logging.info("StatefulSet %s/%s not created yet", namespace, name)
                return False
            pod_name = f"{name}-0"
            ready = self.runner.run(
                [
                    "kubectl",
                    "-n",
                    namespace,
                    "get",
                    "pod",
                    pod_name,
                    "-o",
                    "jsonpath={.status.conditions[?(@.type=='Ready')].status}",
                ],
                capture_output=True,
                check=False,
            )
            if ready.returncode != 0:
                return False
            status = (ready.stdout or "").strip()
            if status == "True":
                logging.info("Pod %s/%s ready", namespace, pod_name)
                return True
            logging.info("Pod %s/%s status=%s", namespace, pod_name, status or "Unknown")
            return False

        wait_for_condition(
            f"statefulset {namespace}/{name} to be ready",
            timeout_seconds=timeout,
            interval=interval,
            check_fn=check,
            raise_on_timeout=True,
        )

    def wait_for_http(self, url: str, timeout: int = 300, interval: int = 1):
        parsed = parse.urlparse(url)
        path = parsed.path or "/"
        if parsed.query:
            path = f"{path}?{parsed.query}"

        def check() -> bool:
            conn = None
            try:
                if (parsed.scheme or "http") == "https":
                    context = ssl._create_unverified_context()
                    conn = http.client.HTTPSConnection(
                        parsed.hostname,
                        parsed.port or 443,
                        timeout=5,
                        context=context,
                    )
                else:
                    conn = http.client.HTTPConnection(
                        parsed.hostname or "localhost",
                        parsed.port or 80,
                        timeout=5,
                    )
                conn.request("GET", path)
                resp = conn.getresponse()
                resp.read()
                return resp.status < 500
            except OSError:
                return False
            finally:
                if conn:
                    conn.close()

        wait_for_condition(
            f"{url} to respond",
            timeout_seconds=timeout,
            interval=interval,
            check_fn=check,
            raise_on_timeout=True,
        )

    def get_secret_json(self, namespace: str, name: str) -> dict:
        result = self.runner.run(
            ["kubectl", "-n", namespace, "get", "secret", name, "-o", "json"],
            capture_output=True,
        )
        return json.loads(result.stdout)

    def read_secret_value(self, namespace: str, name: str, key: str) -> str:
        data = self.get_secret_json(namespace, name)
        encoded = data.get("data", {}).get(key)
        if not encoded:
            raise CommandError(f"Key {key} not found in secret {namespace}/{name}")
        return base64.b64decode(encoded).decode("utf-8").strip()

    def get_git_branch(self) -> str:
        result = self.runner.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True)
        return result.stdout.strip()

    def restart_argocd_server(self):
        result = self.runner.run(
            ["kubectl", "-n", "argocd", "get", "deployment", "argocd-server"],
            check=False,
        )
        if result.returncode != 0:
            logging.info("Argo CD server deployment not available yet; skipping restart.")
            return
        logging.info("Restarting Argo CD server to apply configuration changes...")
        self.runner.run(["kubectl", "-n", "argocd", "rollout", "restart", "deployment", "argocd-server"])
        self.runner.run([
            "kubectl",
            "-n",
            "argocd",
            "rollout",
            "status",
            "deployment",
            "argocd-server",
            "--timeout=180s",
        ], check=False)


class LocalEnvironmentSetup(EnvironmentSetupBase):
    def __init__(self, args: argparse.Namespace):
        super().__init__(args)
        self.kind_cluster_name = args.kind_cluster_name
        self.force_recreate = args.force_recreate_kind
        self.local_ip = args.local_ip or os.environ.get("LOCAL_IP", "")
        self.kubeconfig_file = self.script_dir / ".kind-kubeconfig"
        self.gcp_project_id = (
            args.gcp_project_id
            or os.environ.get("GCP_PROJECT_ID")
            or os.environ.get("TF_VAR_gcp_project_id")
            or "local-dev"
        )

    def run(self):
        try:
            self.setup()
        finally:
            self.cleanup()


    def setup(self):
        self.ensure_binary("kind")
        self.ensure_binary("kubectl")
        self.detect_local_ip()
        self.ensure_kind_cluster()
        self.install_argocd("v3.1.1", "300s")
        self.install_tanka_plugin()
        branch = self.get_git_branch()
        self.apply_root_application(
            "root",
            "environments/argocd-bootstrap",
            [("gitBranch", branch), ("localIP", self.local_ip or "")],
        )
        self.wait_for_root_app("root")
        self.handle_application_waves()
        self.wait_for_namespace("spezistudyplatform", required=True)
        self.wait_for_statefulset_pod_ready("keycloak", "spezistudyplatform")
        self.bootstrap_keycloak()
        self.restart_argocd_server()
        self.show_completion_message()

    def detect_local_ip(self):
        if self.local_ip:
            logging.info("Using provided local IP: %s", self.local_ip)
            return
        helper = self.script_dir / "scripts" / "get-local-ip.sh"
        if helper.exists():
            result = self.runner.run([str(helper)], capture_output=True, check=False)
            ip = (result.stdout or "").strip()
            if ip:
                self.local_ip = ip
                logging.info("Detected local IP: %s", self.local_ip)
                return
        logging.warning(
            "Unable to detect local IP automatically; nip.io hostname will fallback to production domain."
        )
        self.local_ip = ""

    def ensure_kind_cluster(self):
        config = self.script_dir / "local-dev" / "kind-config.yaml"
        logging.info(
            "Ensuring KIND cluster '%s' is available (--force-recreate-kind=%s)",
            self.kind_cluster_name,
            self.force_recreate,
        )
        if self.force_recreate:
            self.runner.run(["kind", "delete", "cluster", "--name", self.kind_cluster_name], check=False)
            self.runner.run([
                "kind",
                "create",
                "cluster",
                "--name",
                self.kind_cluster_name,
                "--config",
                str(config),
            ])
        else:
            clusters = self.runner.run(["kind", "get", "clusters"], capture_output=True)
            existing = clusters.stdout.split()
            if self.kind_cluster_name not in existing:
                self.runner.run([
                    "kind",
                    "create",
                    "cluster",
                    "--name",
                    self.kind_cluster_name,
                    "--config",
                    str(config),
                ])
            else:
                context = f"kind-{self.kind_cluster_name}"
                result = self.runner.run([
                    "kubectl",
                    "cluster-info",
                    "--context",
                    context,
                ], check=False)
                if result.returncode != 0:
                    logging.info("Existing KIND cluster is stale; recreating...")
                    self.runner.run(["kind", "delete", "cluster", "--name", self.kind_cluster_name], check=False)
                    self.runner.run([
                        "kind",
                        "create",
                        "cluster",
                        "--name",
                        self.kind_cluster_name,
                        "--config",
                        str(config),
                    ])
                else:
                    logging.info("Reusing KIND cluster '%s'", self.kind_cluster_name)
        kubeconfig = self.runner.run([
            "kind",
            "get",
            "kubeconfig",
            "--name",
            self.kind_cluster_name,
        ], capture_output=True)
        self.kubeconfig_file.write_text(kubeconfig.stdout)
        os.environ["KUBECONFIG"] = str(self.kubeconfig_file)
        self.runner.env["KUBECONFIG"] = str(self.kubeconfig_file)
        logging.info("KUBECONFIG updated at %s", self.kubeconfig_file)

    def handle_application_waves(self):
        self.wait_for_applications(
            WaveSpec(
                ["local-dev-namespace", "local-dev-cloudnative-pg-crds"],
                "wave 0 applications",
            ),
            timeout=100,
        )
        self.wait_for_applications(
            WaveSpec(["local-dev-auth"], "wave 2 applications"),
            timeout=10,
        )
        self.wait_for_applications(
            WaveSpec(["local-dev-argocd"], "Argo CD application"),
            timeout=100,
        )

    def determine_frontend_url(self) -> str:
        if self.local_ip and self.local_ip != "127.0.0.1":
            domain = f"spezi.{self.local_ip}.nip.io"
            logging.info("Using nip.io development domain %s", domain)
            return f"https://{domain}"
        domain = "platform.spezi.stanford.edu"
        logging.info("Falling back to production domain %s for frontend URL", domain)
        return f"https://{domain}"

    def bootstrap_keycloak(self):
        logging.info("Bootstrapping Keycloak realm and OAuth2 proxy configuration...")
        password = self.read_secret_value("spezistudyplatform", "keycloak", "admin-password")
        self.start_port_forward("spezistudyplatform", "svc/keycloak", "8081:80")
        self.wait_for_http("http://localhost:8081/auth/")
        frontend_url = self.determine_frontend_url()
        tofu_cmd = shutil.which("tofu")
        if not tofu_cmd:
            logging.warning("tofu is not installed; skipping Keycloak bootstrap.")
            return
        tf_dir = self.script_dir / "tofu" / "keycloak-bootstrap" / "tf"
        data_dir = tf_dir / ".terraform-local"
        state_file = tf_dir / "terraform.tfstate.local"
        if self.force_recreate:
            logging.info("Force recreate enabled; clearing local tofu state.")
            shutil.rmtree(data_dir, ignore_errors=True)
            for candidate in tf_dir.glob("terraform.tfstate*"):
                candidate.unlink(missing_ok=True)
        extra_env = {"TF_DATA_DIR": str(data_dir)}
        self.runner.run(
            [tofu_cmd, "init", "-backend=false", "-reconfigure"],
            cwd=tf_dir,
            extra_env=extra_env,
        )
        apply_args = [
            tofu_cmd,
            "apply",
            "-state",
            str(state_file),
            "-state-out",
            str(state_file),
            "-var",
            "keycloak_url=http://localhost:8081/auth",
            "-var",
            f"keycloak_password={password}",
            "-var",
            f"frontend_url={frontend_url}",
            "-var",
            f"gcp_project_id={self.gcp_project_id}",
            "-var",
            "enable_vault_secret_sync=false",
            "-var",
            "create_test_users=true",
            "-auto-approve",
        ]
        self.runner.run(apply_args, cwd=tf_dir, extra_env=extra_env)
        logging.info("Keycloak bootstrap completed successfully.")
        self.sync_oauth2_proxy_secret(state_file)

    def sync_oauth2_proxy_secret(self, state_file: Path):
        if not state_file.exists():
            return
        try:
            state = json.loads(state_file.read_text())
        except json.JSONDecodeError:
            logging.warning("Unable to parse %s; skipping oauth2-proxy secret sync.", state_file)
            return
        secret_value = ""
        for resource in state.get("resources", []):
            if resource.get("type") == "random_password" and resource.get("name") == "oauth2_proxy_client_secret":
                instances = resource.get("instances") or []
                if instances:
                    secret_value = instances[0].get("attributes", {}).get("result", "")
                    break
        if not secret_value:
            logging.warning("oauth2-proxy client secret not found in Terraform state.")
            return
        vault_token = os.environ.get("VAULT_ROOT_TOKEN", "dev-only-token")
        result = self.runner.run([
            "kubectl",
            "-n",
            "vault",
            "get",
            "pods",
            "-l",
            "app=vault",
            "-o",
            "jsonpath={.items[0].metadata.name}",
        ], capture_output=True, check=False)
        vault_pod = (result.stdout or "").strip()
        if not vault_pod:
            logging.warning("Vault pod not available; skipping oauth2-proxy secret sync.")
            return
        logging.info("Syncing oauth2-proxy credential into Vault...")
        self.runner.run(
            [
                "kubectl",
                "-n",
                "vault",
                "exec",
                vault_pod,
                "--",
                "env",
                f"VAULT_TOKEN={vault_token}",
                "VAULT_ADDR=http://127.0.0.1:8200",
                "vault",
                "kv",
                "put",
                "secret/oauth2-proxy-secret",
                "client-id=oauth2-proxy",
                f"client-secret={secret_value}",
                "cookie-secret=local-dev-cookie-secret-32-chars",
            ]
        )
        logging.info("Waiting for oauth2-proxy Kubernetes secret to reflect updated credentials...")

        def secret_matches() -> bool:
            result = self.runner.run([
                "kubectl",
                "-n",
                "spezistudyplatform",
                "get",
                "secret",
                "oauth2-proxy-secret",
                "-o",
                "json",
            ], capture_output=True, check=False)
            if result.returncode != 0 or not result.stdout:
                return False
            try:
                data = json.loads(result.stdout)
            except json.JSONDecodeError:
                return False
            encoded = data.get("data", {}).get("client-secret")
            if not encoded:
                return False
            decoded = base64.b64decode(encoded).decode("utf-8").strip()
            return decoded == secret_value

        wait_for_condition(
            "oauth2-proxy secret sync",
            timeout_seconds=300,
            interval=1,
            check_fn=secret_matches,
        )
        logging.info("Restarting oauth2-proxy deployment to pick up new credentials...")
        self.runner.run([
            "kubectl",
            "-n",
            "spezistudyplatform",
            "rollout",
            "restart",
            "deployment/oauth2-proxy",
        ], check=False)
        self.runner.run([
            "kubectl",
            "-n",
            "spezistudyplatform",
            "rollout",
            "status",
            "deployment",
            "oauth2-proxy",
            "--timeout=120s",
        ], check=False)

    def show_completion_message(self):
        logging.info("Setup complete! Argo CD now manages the local-dev environment.")
        password = self.read_secret_value("argocd", "argocd-initial-admin-secret", "password")
        logging.info("Argo CD admin password: %s", password)
        logging.info(
            "Port-forward the UI with: kubectl port-forward svc/argocd-server -n argocd 8080:443"
        )
        domain = f"spezi.{self.local_ip}.nip.io" if self.local_ip else "localhost"
        logging.info(
            "access: ArgoCD         -> https://%s/argo", domain
        )
        logging.info(
            "access: Main App       -> https://%s", domain
        )
        logging.info(
            "access: Backend        -> https://%s/api", domain
        )
        logging.info(
            "access: Keycloak Admin -> https://%s/auth/admin", domain
        )
        


class ProductionEnvironmentSetup(EnvironmentSetupBase):
    def __init__(self, args: argparse.Namespace):
        super().__init__(args)
        self.project_id = args.gcp_project_id
        self.production_domain = args.production_domain
        self.static_ip = args.static_ip
        self.tf_state_bucket = args.tf_state_bucket
        self.tf_state_prefix = args.tf_state_prefix
        self.gke_tf_state_prefix = args.gke_tf_state_prefix
        self.credentials_file = Path(
            args.credentials_file or (self.script_dir / "gcp-service-account-key.json")
        )
        self.service_account_email = (
            args.service_account_email
            or f"{self.project_id}-svc@{self.project_id}.iam.gserviceaccount.com"
        )
        self.keycloak_realm = args.keycloak_realm
        self.keycloak_base_url = args.keycloak_base_url.rstrip("/")
        self.keycloak_admin_user = args.keycloak_admin_username
        self.keycloak_admin_password = args.keycloak_admin_password
        self.auto_approve = args.auto_approve
        self.action = args.action
        self.terraform_cmd = shutil.which("tofu") or shutil.which("terraform")
        if not self.terraform_cmd:
            raise CommandError("tofu or terraform must be installed")

    def run(self):
        try:
            if self.action == "teardown":
                self.teardown()
            else:
                self.setup()
        finally:
            self.cleanup()

    def check_prereqs(self, setup: bool = True):
        self.ensure_binary("gcloud")
        if setup:
            self.ensure_binary("kubectl")
            self.ensure_binary("ansible-playbook", friendly="ansible-playbook")
            self.ensure_binary("python3")
        self.ensure_binary(self.terraform_cmd or "tofu")

    def ensure_gcloud_login(self):
        result = self.runner.run(
            [
                "gcloud",
                "auth",
                "list",
                "--filter=status:ACTIVE",
                "--format=value(account)",
            ],
            capture_output=True,
        )
        if not result.stdout.strip():
            logging.info("No active gcloud authentication found. Launching gcloud auth login...")
            self.runner.run(["gcloud", "auth", "login"])

    def setup(self):
        self.check_prereqs(setup=True)
        self.ensure_gcloud_login()
        self.configure_project()
        self.runner.env["GOOGLE_APPLICATION_CREDENTIALS"] = str(self.credentials_file)
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(self.credentials_file)
        logging.info("Provisioning GKE infrastructure with Ansible...")
        self.runner.run(["ansible-playbook", "ansible/provision-gke.yaml"])
        self.runner.run(["kubectl", "cluster-info"])
        self.install_argocd("v3.1.4", "600s")
        self.install_tanka_plugin()
        branch = self.get_git_branch()
        self.apply_root_application(
            "root-prod",
            "environments/prod-bootstrap",
            [("gitBranch", branch)],
        )
        self.wait_for_root_app("root-prod")
        self.wait_for_applications(
            WaveSpec(["prod-namespace", "prod-cloudnative-pg-crds"], "wave 0 applications"),
            timeout=600,
        )
        self.wait_for_namespace("spezistudyplatform", required=True)
        self.wait_for_statefulset_pod_ready("keycloak", "spezistudyplatform")
        self.create_external_secret()
        google_client_id = self.bootstrap_keycloak()
        self.wait_for_applications(
            WaveSpec(["prod-argocd"], "Argo CD application"),
            timeout=600,
        )
        self.restart_argocd_server()
        self.show_production_summary(google_client_id)

    def configure_project(self):
        logging.info("Configuring GCP project %s", self.project_id)
        self.runner.run(["gcloud", "config", "set", "project", self.project_id])
        logging.info("Enabling required APIs...")
        for api in [
            "secretmanager.googleapis.com",
            "iamcredentials.googleapis.com",
            "cloudresourcemanager.googleapis.com",
            "iap.googleapis.com",
        ]:
            self.runner.run(["gcloud", "services", "enable", api, f"--project={self.project_id}"])
        if not self.credentials_file.exists():
            logging.info("Creating service account key at %s", self.credentials_file)
            self.runner.run([
                "gcloud",
                "iam",
                "service-accounts",
                "keys",
                "create",
                str(self.credentials_file),
                f"--iam-account={self.service_account_email}",
            ])
        else:
            logging.info("Reusing existing service account key %s", self.credentials_file)
        self.runner.run([
            "gcloud",
            "auth",
            "activate-service-account",
            f"--key-file={self.credentials_file}",
        ])
        self.ensure_state_bucket()
        self.ensure_service_account_roles()
        self.update_ansible_group_vars()

    def ensure_state_bucket(self):
        bucket = f"gs://{self.tf_state_bucket}"
        result = self.runner.run(["gsutil", "ls", bucket], check=False)
        if result.returncode != 0:
            logging.info("Creating terraform state bucket %s", bucket)
            self.runner.run(["gsutil", "mb", "-p", self.project_id, "-l", "us-west1", bucket])
            self.runner.run(["gsutil", "versioning", "set", "on", bucket])
        else:
            logging.info("Terraform state bucket already exists: %s", bucket)

    def ensure_service_account_roles(self):
        roles = [
            "roles/storage.admin",
            "roles/container.admin",
            "roles/compute.admin",
            "roles/iam.serviceAccountUser",
            "roles/secretmanager.secretAccessor",
        ]
        for role in roles:
            cmd = [
                "gcloud",
                "projects",
                "get-iam-policy",
                self.project_id,
                "--flatten=bindings[].members",
                "--format=value(bindings.role)",
                f"--filter=bindings.members:serviceAccount:{self.service_account_email} AND bindings.role:{role}",
            ]
            result = self.runner.run(cmd, capture_output=True, check=False)
            if role not in (result.stdout or ""):
                logging.info("Granting role %s to %s", role, self.service_account_email)
                self.runner.run([
                    "gcloud",
                    "projects",
                    "add-iam-policy-binding",
                    self.project_id,
                    f"--member=serviceAccount:{self.service_account_email}",
                    f"--role={role}",
                ])

    def update_ansible_group_vars(self):
        group_vars = self.script_dir / "ansible" / "group_vars" / "all.yaml"
        if not group_vars.exists():
            return
        content = group_vars.read_text().splitlines()
        updated = False
        for idx, line in enumerate(content):
            if line.strip().startswith("gcp_credentials_file:"):
                content[idx] = f"gcp_credentials_file: \"{self.credentials_file}\""
                updated = True
                break
        if not updated:
            content.append(f"gcp_credentials_file: \"{self.credentials_file}\"")
        group_vars.write_text("\n".join(content) + "\n")
        logging.info("Updated ansible/group_vars/all.yaml with credentials path.")

    def create_external_secret(self):
        logging.info("Creating GCP service account secret for External Secrets...")
        self.runner.run(
            "kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -"
        )
        self.runner.run(
            f"kubectl create secret generic gcp-sa-key --from-file=secret-access-credentials={self.credentials_file} -n external-secrets-system --dry-run=client -o yaml | kubectl apply -f -"
        )

    def _fetch_google_sso_secrets(self) -> Tuple[str, str]:
        """Fetch Google SSO client credentials from GCP Secret Manager via gcloud."""
        client_id = ""
        client_secret = ""
        for secret_name, label in [
            ("keycloak-google-sso-client-id", "client ID"),
            ("keycloak-google-sso-client-secret", "client secret"),
        ]:
            result = self.runner.run(
                [
                    "gcloud", "secrets", "versions", "access", "latest",
                    f"--secret={secret_name}",
                    f"--project={self.project_id}",
                ],
                capture_output=True,
                check=False,
            )
            value = (result.stdout or "").strip()
            if result.returncode != 0 or not value:
                logging.warning(
                    "Could not fetch Google SSO %s from Secret Manager; Google IDP will be skipped.",
                    label,
                )
                return "", ""
            if secret_name.endswith("client-id"):
                client_id = value
            else:
                client_secret = value
        logging.info("Fetched Google SSO credentials from Secret Manager.")
        return client_id, client_secret

    def bootstrap_keycloak(self) -> str:
        logging.info("Bootstrapping Keycloak realm for production...")
        self.start_port_forward("spezistudyplatform", "svc/keycloak", "8081:80")
        self.wait_for_http(f"{self.keycloak_base_url}/")
        if not self.keycloak_admin_password:
            self.keycloak_admin_password = self.read_secret_value(
                "spezistudyplatform", "keycloak", "admin-password"
            )
        if not self.keycloak_admin_user:
            try:
                username = self.read_secret_value(
                    "spezistudyplatform", "keycloak", "admin-username"
                )
            except CommandError:
                logging.warning("Keycloak secret missing admin-username; defaulting to 'user'.")
                username = ""
            self.keycloak_admin_user = username or "user"
        logging.info("Using Keycloak admin username: %s", self.keycloak_admin_user)
        google_client_id, google_client_secret = self._fetch_google_sso_secrets()
        tf_dir = self.script_dir / "tofu" / "keycloak-bootstrap" / "tf"
        backend_file = tf_dir / "backend-prod.tf"
        backend_file.write_text("terraform {\n  backend \"gcs\" {}\n}\n")
        extra_env = {
            "TF_VAR_keycloak_password": self.keycloak_admin_password,
            "TF_VAR_keycloak_username": self.keycloak_admin_user,
            "TF_VAR_keycloak_client_id": "admin-cli",
            "TF_VAR_keycloak_url": self.keycloak_base_url,
            "TF_VAR_gcp_project_id": self.project_id,
            "TF_VAR_google_oauth_client_id": google_client_id,
            "TF_VAR_google_oauth_client_secret": google_client_secret,
            "TF_VAR_create_test_users": "false",
        }
        try:
            self.runner.run(
                [
                    self.terraform_cmd,
                    "init",
                    "-migrate-state",
                    f"-backend-config=bucket={self.tf_state_bucket}",
                    f"-backend-config=prefix={self.tf_state_prefix}",
                ],
                cwd=tf_dir,
            )
            lock_object = f"gs://{self.tf_state_bucket}/{self.tf_state_prefix}/default.tflock"
            self.runner.run(["gsutil", "ls", lock_object], check=False)
            self.runner.run(["gsutil", "rm", lock_object], check=False)
            self.runner.run(
                [
                    self.terraform_cmd,
                    "apply",
                    f"-var=keycloak_url={self.keycloak_base_url}",
                    f"-var=frontend_url=https://{self.production_domain}",
                    f"-var=gcp_project_id={self.project_id}",
                    "-auto-approve",
                ],
                cwd=tf_dir,
                extra_env=extra_env,
            )
        finally:
            backend_file.unlink(missing_ok=True)
        logging.info("Keycloak bootstrap completed for production.")
        try:
            client_secret = fetch_keycloak_client_secret(
                self.keycloak_base_url,
                self.keycloak_realm,
                self.keycloak_admin_user,
                self.keycloak_admin_password,
                "argocd",
            )
        except CommandError as exc:
            logging.warning(
                "Skipping Argo CD client secret sync because Keycloak did not return one: %s",
                exc,
            )
        else:
            self.store_secret_in_gcp("keycloak-argocd-client", client_secret)
        result = self.runner.run(
            [
                "gcloud",
                "secrets",
                "versions",
                "access",
                "latest",
                "--secret=keycloak-google-sso-client-id",
                f"--project={self.project_id}",
            ],
            capture_output=True,
            check=False,
        )
        google_client_id = result.stdout.strip() or "stored-in-secret-manager"
        logging.info("Google OAuth client info stored in Secret Manager.")
        return google_client_id

    def store_secret_in_gcp(self, name: str, value: str):
        create = self.runner.run(
            [
                "gcloud",
                "secrets",
                "create",
                name,
                f"--project={self.project_id}",
                "--data-file=-",
            ],
            input=value,
            check=False,
        )
        if create.returncode != 0:
            self.runner.run(
                [
                    "gcloud",
                    "secrets",
                    "versions",
                    "add",
                    name,
                    f"--project={self.project_id}",
                    "--data-file=-",
                ],
                input=value,
            )

    def show_production_summary(self, google_client_id: str):
        logging.info("Production setup complete! Argo CD now manages the production environment.")
        logging.info("Production URL: https://%s", self.production_domain)
        logging.info("Static IP configured: %s", self.static_ip)
        logging.info("Google OAuth Client ID: %s", google_client_id)
        password = self.read_secret_value("argocd", "argocd-initial-admin-secret", "password")
        logging.info("Argo CD admin password: %s", password)
        logging.info(
            "Port-forward the UI with: kubectl port-forward svc/argocd-server -n argocd 8080:443"
        )

    def teardown(self):
        self.check_prereqs(setup=False)
        self.ensure_gcloud_login()
        self.runner.run(["gcloud", "config", "set", "project", self.project_id])
        if not self.credentials_file.exists():
            raise CommandError(
                f"Service account key not found at {self.credentials_file}; run setup before teardown."
            )
        self.runner.run([
            "gcloud",
            "auth",
            "activate-service-account",
            f"--key-file={self.credentials_file}",
        ])
        self.runner.env["GOOGLE_APPLICATION_CREDENTIALS"] = str(self.credentials_file)
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(self.credentials_file)
        self.destroy_gke_infrastructure()

    def destroy_gke_infrastructure(self):
        terraform_dir = self.script_dir / "tofu" / "gke"
        backend_file = terraform_dir / "backend-prod.tf"
        backend_file.write_text("terraform {\n  backend \"gcs\" {}\n}\n")
        try:
            self.runner.run(
                [
                    self.terraform_cmd,
                    "init",
                    "-migrate-state",
                    f"-backend-config=bucket={self.tf_state_bucket}",
                    f"-backend-config=prefix={self.gke_tf_state_prefix}",
                ],
                cwd=terraform_dir,
            )
            lock_object = f"gs://{self.tf_state_bucket}/{self.gke_tf_state_prefix}/default.tflock"
            self.runner.run(["gsutil", "ls", lock_object], check=False)
            self.runner.run(["gsutil", "rm", lock_object], check=False)
            if not self.auto_approve:
                response = input(
                    "This will destroy the production GKE cluster and associated resources (static IP kept). Proceed? [y/N] "
                ).strip().lower()
                if response not in {"y", "yes"}:
                    logging.info("Teardown cancelled by user.")
                    return
            state = self.runner.run(
                [self.terraform_cmd, "state", "list"],
                capture_output=True,
                check=False,
                cwd=terraform_dir,
            )
            if state.returncode != 0:
                raise CommandError("Unable to read Terraform state; aborting teardown.")
            resources = [line.strip() for line in state.stdout.splitlines() if line.strip()]
            targets = [
                f"-target={res}"
                for res in resources
                if res != "google_compute_address.ip_address"
            ]
            if targets:
                cmd = [self.terraform_cmd, "destroy", "-auto-approve", *targets]
                self.runner.run(cmd, cwd=terraform_dir)
            else:
                logging.info("No Terraform-managed resources to destroy.")
        finally:
            backend_file.unlink(missing_ok=True)


def fetch_keycloak_client_secret(
    base_url: str,
    realm: str,
    admin_user: str,
    admin_password: str,
    client_id: str,
) -> str:
    token = request_keycloak_token(base_url, admin_user, admin_password)
    if not token:
        raise CommandError("Failed to obtain Keycloak admin token")
    client_uuid = request_keycloak_client_uuid(base_url, realm, client_id, token)
    if not client_uuid:
        raise CommandError(f"Client {client_id} not found in realm {realm}")
    secret_url = f"{base_url}/admin/realms/{realm}/clients/{client_uuid}/client-secret"
    req = request.Request(secret_url, headers={"Authorization": f"Bearer {token}"})
    with request.urlopen(req, timeout=30) as resp:  # noqa: S310
        payload = json.loads(resp.read().decode("utf-8"))
    secret = payload.get("value")
    if not secret:
        raise CommandError("Keycloak did not return a client secret")
    return secret


def request_keycloak_token(base_url: str, username: str, password: str) -> str:
    token_url = f"{base_url}/realms/master/protocol/openid-connect/token"
    data = parse.urlencode(
        {
            "client_id": "admin-cli",
            "username": username,
            "password": password,
            "grant_type": "password",
        }
    ).encode()
    req = request.Request(
        token_url,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with request.urlopen(req, timeout=30) as resp:  # noqa: S310
            payload = json.loads(resp.read().decode("utf-8"))
            return payload.get("access_token", "")
    except urlerror.URLError as exc:  # pragma: no cover - network path
        logging.error("Failed to request Keycloak token: %s", exc)
        return ""


def request_keycloak_client_uuid(
    base_url: str, realm: str, client_id: str, token: str
) -> str:
    url = f"{base_url}/admin/realms/{realm}/clients?clientId={parse.quote(client_id)}"
    req = request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with request.urlopen(req, timeout=30) as resp:  # noqa: S310
        payload = json.loads(resp.read().decode("utf-8"))
    if isinstance(payload, list) and payload:
        return payload[0].get("id", "")
    return ""



def apply_default_arguments(args: argparse.Namespace) -> argparse.Namespace:
    defaults = LOCAL_DEFAULTS if args.command == "local" else PROD_DEFAULTS
    for key, value in defaults.items():
        if not hasattr(args, key):
            setattr(args, key, value)
    return args


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage local and production environment setup")
    parser.add_argument("--verbose", action="store_true", help="Enable debug logging")
    subparsers = parser.add_subparsers(dest="command", required=True)

    local_parser = subparsers.add_parser("local", help="Bootstrap the local KIND environment")
    local_parser.add_argument(
        "--kind-cluster-name",
        default=argparse.SUPPRESS,
        help=f"Name of the KIND cluster (default: {LOCAL_DEFAULTS['kind_cluster_name']})",
    )
    local_parser.add_argument(
        "--force-recreate-kind",
        dest="force_recreate_kind",
        action="store_true",
        default=argparse.SUPPRESS,
        help="Recreate the KIND cluster before provisioning",
    )
    local_parser.add_argument(
        "--no-force-recreate-kind",
        dest="force_recreate_kind",
        action="store_false",
        default=argparse.SUPPRESS,
        help="Reuse existing KIND cluster if possible",
    )
    local_parser.add_argument(
        "--local-ip",
        default=argparse.SUPPRESS,
        help=(
            "Override detected local IP for nip.io domain "
            f"(default: {LOCAL_DEFAULTS['local_ip'] or 'auto-detect'})"
        ),
    )
    local_parser.add_argument(
        "--gcp-project-id",
        default=argparse.SUPPRESS,
        help=(
            "Override GCP project id used for Keycloak bootstrap "
            f"(default: {LOCAL_DEFAULTS['gcp_project_id'] or 'env/auto-detect'})"
        ),
    )
    prod_parser = subparsers.add_parser("prod", help="Provision or tear down production infrastructure")
    prod_parser.add_argument(
        "--action",
        choices=["setup", "teardown"],
        default=argparse.SUPPRESS,
        help=f"Action to perform (default: {PROD_DEFAULTS['action']})",
    )
    prod_parser.add_argument(
        "--gcp-project-id",
        default=argparse.SUPPRESS,
        help=f"GCP project id (default: {PROD_DEFAULTS['gcp_project_id']})",
    )
    prod_parser.add_argument(
        "--production-domain",
        default=argparse.SUPPRESS,
        help=f"Primary domain for the platform (default: {PROD_DEFAULTS['production_domain']})",
    )
    prod_parser.add_argument(
        "--static-ip",
        default=argparse.SUPPRESS,
        help=f"Reserved static IP address (default: {PROD_DEFAULTS['static_ip']})",
    )
    prod_parser.add_argument(
        "--tf-state-bucket",
        default=argparse.SUPPRESS,
        help=f"Terraform state bucket (default: {PROD_DEFAULTS['tf_state_bucket']})",
    )
    prod_parser.add_argument(
        "--tf-state-prefix",
        default=argparse.SUPPRESS,
        help=f"Terraform state prefix (default: {PROD_DEFAULTS['tf_state_prefix']})",
    )
    prod_parser.add_argument(
        "--gke-tf-state-prefix",
        default=argparse.SUPPRESS,
        help=f"GKE Terraform state prefix (default: {PROD_DEFAULTS['gke_tf_state_prefix']})",
    )
    prod_parser.add_argument(
        "--service-account-email",
        default=argparse.SUPPRESS,
        help=(
            "Service account email used for provisioning "
            f"(default: {PROD_DEFAULTS['service_account_email'] or 'derive from project'})"
        ),
    )
    prod_parser.add_argument(
        "--credentials-file",
        default=argparse.SUPPRESS,
        help=(
            "Path to the GCP service account key file "
            f"(default: {PROD_DEFAULTS['credentials_file'] or 'repo root gcp-service-account-key.json'})"
        ),
    )
    prod_parser.add_argument(
        "--keycloak-realm",
        default=argparse.SUPPRESS,
        help=f"Keycloak realm name (default: {PROD_DEFAULTS['keycloak_realm']})",
    )
    prod_parser.add_argument(
        "--keycloak-base-url",
        default=argparse.SUPPRESS,
        help=f"Keycloak base URL (default: {PROD_DEFAULTS['keycloak_base_url']})",
    )
    prod_parser.add_argument(
        "--keycloak-admin-username",
        default=argparse.SUPPRESS,
        help=(
            "Keycloak admin username (default: value in Kubernetes secret or "
            f"{PROD_DEFAULTS['keycloak_admin_username'] or 'auto-detect'})"
        ),
    )
    prod_parser.add_argument(
        "--keycloak-admin-password",
        default=argparse.SUPPRESS,
        help="Keycloak admin password (default: value in Kubernetes secret)",
    )
    prod_parser.add_argument(
        "--auto-approve",
        "--yes",
        dest="auto_approve",
        action="store_true",
        default=argparse.SUPPRESS,
        help=(
            "Skip confirmation prompts during destructive actions "
            f"(default: {PROD_DEFAULTS['auto_approve']})"
        ),
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    args = apply_default_arguments(args)
    configure_logging(args.verbose)
    if args.command == "local":
        runner = LocalEnvironmentSetup(args)
    else:
        runner = ProductionEnvironmentSetup(args)
    try:
        runner.run()
    except (CommandError, RuntimeError) as exc:
        logging.error("%s", exc)
        sys.exit(1)


if __name__ == "__main__":
    main()
