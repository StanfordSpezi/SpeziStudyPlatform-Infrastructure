# GEMINI.md

This document contains instructions and context for the Gemini agent working in this repository.

## Architecture

This repository contains infrastructure for the Spezi Study Platform using a GitOps approach with ArgoCD and Tanka/Jsonnet for Kubernetes deployments.

### Key Components:
- **environments/**: Tanka environments (local-dev, default, prod-bootstrap, argocd-bootstrap)
- **lib/platform/**: Jsonnet libraries for platform components (auth, backend, frontend, etc.)
- **tofu/**: OpenTofu/Terraform configurations for infrastructure provisioning
- **kube/**: Raw Kubernetes YAML manifests
- **setup-tanka.sh**: Automated setup script for local development environment

### Technology Stack:
- **Tanka**: Kubernetes configuration management using Jsonnet
- **ArgoCD**: GitOps continuous deployment
- **OpenTofu**: Infrastructure as Code (Terraform alternative)
- **Kind**: Local Kubernetes clusters for development
- **Keycloak**: Identity and access management
- **PostgreSQL**: Primary database (via CloudNative-PG operator)
- **Traefik**: Ingress controller and reverse proxy

## Common Commands

### Local Development Setup
```bash
# Full automated setup (creates KIND cluster, installs ArgoCD, deploys applications)
./setup-tanka.sh
```

### Testing Local Development Flow
To test the complete local development setup:

```bash
# 1. Delete existing KIND cluster
kind delete cluster --name=spezi-study-platform

# 2. Re-bootstrap the entire cluster
./setup-tanka.sh

# 3. Success indicator: Look for ArgoCD access instructions in the output
# You should see a log line explaining how to access ArgoCD UI
```

### Environment Management
```bash
# Deploy specific environment with Tanka
tk apply environments/local-dev

# Deploy specific component
tk apply environments/local-dev --component=backend

# Show diff before applying
tk diff environments/local-dev
```

### Infrastructure Provisioning
```bash
# Initialize and apply Keycloak bootstrap (run from tofu/keycloak-bootstrap/tf/)
tofu init

# For production environment, first port-forward to Keycloak, then apply
kubectl port-forward -n spezistudyplatform svc/keycloak 8081:80 &
tofu apply -var="keycloak_url=http://localhost:8081/auth" -var="keycloak_password=admin123!" -var="frontend_url=https://platform.spezi.stanford.edu" -auto-approve
```

### Kubernetes Operations
```bash
# Port forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Port forward Keycloak
kubectl port-forward -n spezistudyplatform svc/keycloak 8081:80
```

### Docker Compose (Alternative Local Setup)
```bash
# Start local services
docker-compose up -d

# View logs
docker-compose logs -f
```

## Environment Structure

Each Tanka environment follows this pattern:
- **main.jsonnet**: Environment definition with component imports
- Components are modular and configured via `lib/platform/config.libsonnet`
- Sealed secrets stored in environment-specific directories

### Wave-based Deployment:
1. **Wave 0**: Critical infrastructure (namespaces, CRDs)
2. **Wave 1**: Operators and controllers (CloudNative-PG)
3. **Wave 2**: Applications (backend, frontend, auth)

## Configuration Management

- **lib/platform/config.libsonnet**: Central configuration for different environments
- Environment-specific overrides in each environment's main.jsonnet
- Secrets managed via Sealed Secrets or external secret management

## Prerequisites

Required tools:
- `kubeseal` (brew install kubeseal)
- `google-cloud-sdk` (brew install google-cloud-sdk)
- `tofu` or `terraform` (for infrastructure provisioning)
- `kind` (for local Kubernetes clusters)
- `tanka` (brew install tanka)

Optional:
- `k9s` (brew install k9s) - recommended for cluster management

## Code Style and Commit Guidelines

**IMPORTANT**: When making commits, do NOT add any flashy elements, emojis, or specific attribution. Keep commit messages simple and professional.