# Local Development Setup with KIND

This guide explains how to set up a local development environment using KIND (Kubernetes in Docker) with ArgoCD and Tanka.

## Prerequisites

*   [Docker](https://docs.docker.com/get-docker/)
*   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
*   [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)

## Setup

1.  **Start the local Kubernetes cluster:**

    ```bash
    ./setup-tanka.sh
    ```

    This script will:
    *   Create a KIND cluster.
    *   Install ArgoCD with Tanka Config Management Plugin.
    *   Bootstrap ArgoCD applications that will deploy the platform components automatically.
    *   Deploy all services using GitOps approach.

2.  **Access the services:**

    The services will be available at `http://spezi.127.0.0.1.nip.io`.

    *   Frontend: `http://spezi.127.0.0.1.nip.io`
    *   Backend: `http://spezi.127.0.0.1.nip.io/backend`
    *   Keycloak: `http://spezi.127.0.0.1.nip.io/auth`
    *   ArgoCD UI: `kubectl port-forward svc/argocd-server -n argocd 8080:443`

3.  **Monitor deployment:**

    ```bash
    kubectl get applications -n argocd
    ```

## Teardown

To delete the local cluster:

```bash
kind delete cluster --name spezi-study-platform
```
