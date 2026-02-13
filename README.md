# Spezi Study Platform Infrastructure

This repository contains the infrastructure definitions for the Spezi Study Platform, managed with a GitOps approach using ArgoCD and Tanka.

The repo has been tested to work on unix-based distros, specifically WSL2 and macOS. For anything else, YMMV.

## Prerequisites
(Note that we assume [Homebrew](https://brew.sh/) is installed prior to installing the rest of these, but you are welcome to install them however you wish)

Before you begin, ensure you have the following tools installed:

- **kind**: For running local Kubernetes clusters. (`brew install kind`)
- **kubectl**: For interacting with Kubernetes clusters. (`brew install kubernetes-cli`)
- **tofu** (or **terraform**): For infrastructure as code provisioning. (`brew install opentofu`)
- **Google Cloud SDK/CLI**: Required for production deployments. (`brew install google-cloud-sdk`)

### Python Dependencies

This project uses Python for setup and integration testing. Install the required packages using pip:

```bash
python3 -m pip install -r ansible/requirements.txt
```

## Local Development

To set up a complete local development environment, run the unified setup script:

```bash
python3 tools/spezi_setup/spezi_setup.py local
```

This script will:

1.  Create a local Kubernetes cluster using **KIND**.
2.  Install and configure **ArgoCD**.
3.  Deploy all platform applications (e.g., backend, frontend, auth).
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

## Production Environment

The setup script also supports provisioning and managing a production environment on Google Kubernetes Engine (GKE). 
NOTE: This requires production (GCP) json keys, which are obtained from the GCP console or CLI.

### Setup

To provision the production infrastructure, use the `prod` command:

```bash
python3 tools/spezi_setup/spezi_setup.py prod --action setup [OPTIONS]
```

This requires additional configuration, such as GCP project ID, domain, and credentials. Run `python3 tools/spezi_setup/spezi_setup.py prod --help` for a full list of options.

### Teardown

To tear down the production infrastructure:

```bash
python3 tools/spezi_setup/spezi_setup.py prod --action teardown [OPTIONS]
```

**Caution**: This is a destructive operation and will remove the GKE cluster and associated resources.

## Optional Tools

- **k9s**: A terminal-based UI to manage your Kubernetes cluster. (`brew install k9s`)
