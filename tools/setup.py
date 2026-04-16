#!/usr/bin/env python3
"""Bootstrap script for Spezi Study Platform.

Installs ArgoCD via Helm, then hands off to ArgoCD's app-of-apps pattern.
Works for both dev (KIND) and prod (real cluster).

Usage:
    python tools/setup.py                    # dev, current git branch
    python tools/setup.py --branch feature   # dev, specific branch
    python tools/setup.py --env prod         # prod, main branch
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARGOCD_CHART_VERSION = "9.5.1"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    print(f"  $ {' '.join(cmd)}")
    return subprocess.run(cmd, check=True, **kwargs)


def kubectl(*args: str, **kwargs) -> subprocess.CompletedProcess:
    return run(["kubectl", *args], **kwargs)


def helm(*args: str, **kwargs) -> subprocess.CompletedProcess:
    return run(["helm", *args], **kwargs)


def get_current_branch() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        capture_output=True, text=True, check=True, cwd=ROOT,
    )
    return result.stdout.strip()


def branch_exists_on_remote(branch: str) -> bool:
    result = subprocess.run(
        ["git", "ls-remote", "--heads", "origin", branch],
        capture_output=True, text=True, cwd=ROOT,
    )
    return branch in result.stdout


def header(msg: str):
    print(f"\n{'=' * 60}\n  {msg}\n{'=' * 60}\n")


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------


def step_install_argocd():
    header("Step 1/3: Install ArgoCD")
    helm("repo", "add", "argo",
         "https://argoproj.github.io/argo-helm", "--force-update")
    helm("repo", "update")
    helm("upgrade", "--install", "argocd", "argo/argo-cd",
         "--namespace=argocd", "--create-namespace",
         f"--version={ARGOCD_CHART_VERSION}",
         "--wait", "--timeout=5m")

    print("\nWaiting for ArgoCD server...")
    kubectl("wait", "deployment/argocd-server", "-n", "argocd",
            "--for=condition=Available", "--timeout=300s")


def step_bootstrap_config(env: str):
    """Pre-apply only ConfigMaps and Namespace from bootstrap overlay.

    Certificate and IngressRoute CRDs don't exist yet (cert-manager and
    Traefik are installed later by ArgoCD). The full bootstrap overlay is
    synced by the ArgoCD bootstrap Application after operators are ready.
    """
    header("Step 2/3: Pre-apply bootstrap config")
    rendered = subprocess.run(
        ["kubectl", "kustomize", str(ROOT / "bootstrap" / env)],
        capture_output=True, text=True, check=True,
    ).stdout

    safe_kinds = {"ConfigMap", "Namespace"}
    docs = []
    for doc in rendered.split("---"):
        doc = doc.strip()
        if not doc:
            continue
        for line in doc.splitlines():
            if line.startswith("kind:"):
                kind = line.split(":", 1)[1].strip()
                if kind in safe_kinds:
                    docs.append(doc)
                break

    if docs:
        filtered = "\n---\n".join(docs)
        kubectl("apply", "-f", "-", input=filtered, text=True)


def step_root_application(env: str, branch: str):
    header("Step 3/3: Apply root Application")
    rendered = subprocess.run(
        ["kubectl", "kustomize", str(ROOT / "argocd-apps" / env)],
        capture_output=True, text=True, check=True,
    ).stdout

    if env == "dev":
        rendered = rendered.replace(
            "targetRevision: main", f"targetRevision: {branch}")

    kubectl("apply", "-f", "-", input=rendered, text=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Bootstrap Spezi Study Platform")
    parser.add_argument(
        "--env", choices=["dev", "prod"], default="dev",
        help="Target environment (default: dev)")
    parser.add_argument(
        "--branch",
        help="Git branch for ArgoCD to track (dev only, default: current branch)")
    args = parser.parse_args()

    branch = args.branch or get_current_branch()

    if args.env == "dev":
        if not branch_exists_on_remote(branch):
            print(f"\nError: Branch '{branch}' not found on remote 'origin'.")
            print("Push your branch first: git push -u origin HEAD")
            sys.exit(1)
        print(f"  Branch: {branch}")

    step_install_argocd()
    step_bootstrap_config(args.env)
    step_root_application(args.env, branch)

    domain = "localhost" if args.env == "dev" else "platform.spezi.stanford.edu"
    print(f"""
=====================================
  Bootstrap complete!
=====================================
  ArgoCD will now sync all resources.
  Monitor: kubectl get applications -n argocd

  Main App:        https://{domain}
  Server API:      https://{domain}/api
  Keycloak Admin:  https://{domain}/auth/admin
  ArgoCD:          https://{domain}/argo
=====================================
""")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        print(f"\nFailed: {e}", file=sys.stderr)
        sys.exit(1)
