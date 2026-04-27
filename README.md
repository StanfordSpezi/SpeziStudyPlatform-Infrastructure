# Spezi Study Platform Infrastructure

This repository contains the infrastructure definitions for the Spezi Study Platform, managed with a GitOps approach using ArgoCD, Helm, and Kustomize.

The repo has been tested to work on unix-based distros, specifically WSL2 and macOS. For anything else, YMMV.

## Prerequisites
(Note that we assume [Homebrew](https://brew.sh/) is installed prior to installing the rest of these, but you are welcome to install them however you wish)

Before you begin, ensure you have the following tools installed:

- **kind**: For running local Kubernetes clusters. (`brew install kind`)
- **kubectl**: For interacting with Kubernetes clusters. (`brew install kubernetes-cli`)
- **helm**: For managing Kubernetes charts. (`brew install helm`)
- **python3**: For running the setup script.

## Local Development

```bash
# One-time: create the KIND cluster
kind create cluster --config tools/kind-config.yaml

# Push your branch (ArgoCD syncs from GitHub)
git push -u origin HEAD

# Bootstrap ArgoCD, which then manages everything
make dev
# or: python3 tools/setup.py
# or: python3 tools/setup.py --branch my-feature

# Monitor sync progress
make dev-status
```

The setup script installs ArgoCD via Helm, then applies a root Application that triggers the app-of-apps pattern. ArgoCD syncs operators, infrastructure, and application workloads via sync waves.

### Forcing a Clean Setup

```bash
# Delete and recreate the cluster
make dev-recreate
```

## Integration Tests

After setting up the local environment, you can run the end-to-end integration tests to verify the authentication and routing functionality.

The test script is automatically configured by the local setup process. To run the tests:

```bash
python3 tools/run_integration_tests.py --insecure
```

The `--insecure` flag is required to handle the self-signed certificates used in the local dev environment.

The script will test:
-   Login with an authorized user (`testuser`/`password123`).
-   Denial of an unauthorized user (`testuser2`/`password456`).
-   Rejection of invalid credentials.

You can customize the test credentials using command-line arguments (e.g., `--username`, `--password`).

## Docker Local Development

For running backing services (PostgreSQL, Keycloak) or the full stack without Kubernetes, see the [Docker setup guide](docker/README.md). This is the recommended approach when developing the [Server](https://github.com/StanfordSpezi/SpeziStudyPlatform-Server) or [Web](https://github.com/StanfordSpezi/SpeziStudyPlatform-Web) repositories locally.

## Optional Tools

- **k9s**: A terminal-based UI to manage your Kubernetes cluster. (`brew install k9s`)
