# Spezi Study Platform Infrastructure

This repository contains the infrastructure definitions for the Spezi Study Platform, managed with a GitOps approach using ArgoCD and Tanka.

The repo has been tested to work on unix-based distros, specifically WSL2 and macOS. For anything else, YMMV.

## Prerequisites
(Note that we assume [Homebrew](https://brew.sh/) is installed prior to installing the rest of these, but you are welcome to install them however you wish)

Before you begin, ensure you have the following tools installed:

- **kind**: For running local Kubernetes clusters. (`brew install kind`)
- **kubectl**: For interacting with Kubernetes clusters. (`brew install kubernetes-cli`)
- **tofu** (or **terraform**): For infrastructure as code provisioning. (`brew install opentofu`)

## Local Development

To set up a complete local development environment, run the unified setup script:

```bash
python3 tools/spezi_setup/spezi_setup.py local
```

This script will:

1.  Create a local Kubernetes cluster using **KIND**.
2.  Install and configure **ArgoCD**.
3.  Deploy all platform applications (e.g., server, web, auth).
4.  Bootstrap **Keycloak** with a default realm and test users.

Upon completion, you will see access instructions for ArgoCD and other services.

### Forcing a Clean Setup

If you need to start fresh, you can force the script to recreate the KIND cluster:

```bash
python3 tools/spezi_setup/spezi_setup.py local --force-recreate-kind
```

## Integration Tests

After setting up the local environment, you can run the end-to-end integration tests to verify the authentication and routing functionality.

The test script is automatically configured by the local setup process. To run the tests:

```bash
python3 tools/run_integration_tests.py --insecure
```

The `--insecure` flag is required to handle the self-signed certificates used in the local `nip.io` domain.

The script will test:
-   Login with an authorized user (`testuser`/`password123`).
-   Denial of an unauthorized user (`testuser2`/`password456`).
-   Rejection of invalid credentials.

You can customize the test credentials using command-line arguments (e.g., `--username`, `--password`).

## Optional Tools

- **k9s**: A terminal-based UI to manage your Kubernetes cluster. (`brew install k9s`)
