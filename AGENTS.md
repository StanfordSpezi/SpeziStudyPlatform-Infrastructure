<!--
This source file is part of the Stanford Spezi open source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
-->

# AGENTS.md

Guidance for AI coding assistants (Claude, ChatGPT, Gemini, etc.) contributing to this repository. Read this first so you can follow the conventions and tooling the rest of the team expects.

## Architecture Overview

The Spezi Study Platform uses a GitOps workflow where Argo CD manages Kubernetes resources via native Helm and Kustomize support (no plugins). Both dev and prod use the same deployment mechanism: ArgoCD app-of-apps.

### Directory structure

- `apps/`: Application workloads (server, web) with base/dev/prod Kustomize overlays.
- `infrastructure/`: Shared infrastructure (DB, Keycloak, networking, secrets) with base/dev/prod overlays.
- `bootstrap/`: ArgoCD's own configuration (namespace, RBAC, ConfigMaps, ingress, certs) with base/dev/prod overlays.
- `argocd-apps/`: ArgoCD Application manifests (app-of-apps pattern) with base/dev/prod overlays.
- `tools/`: KIND config, setup script, integration tests.

### Layering

The three Kustomize trees (`apps/`, `infrastructure/`, `bootstrap/`) are deployed as separate ArgoCD Applications with independent sync waves. This separation means:

- `apps/` changes with application releases (image tags, env vars).
- `infrastructure/` changes rarely (DB config, networking, secrets).
- `bootstrap/` changes only when ArgoCD itself needs reconfiguration.

### Sync Waves (managed by ArgoCD)

- **Wave 0:** Operators (cert-manager, CNPG, External Secrets) via Helm.
- **Wave 1:** Traefik (Helm), bootstrap (Kustomize), infrastructure (Kustomize).
- **Wave 2:** Application workloads (Kustomize).

ArgoCD gates each wave on resource health before proceeding.

## Setup (tools/setup.py)

The setup script bootstraps ArgoCD, then ArgoCD manages everything else. Same flow for dev and prod.

### Local KIND environment

```bash
# One-time: create the KIND cluster
kind create cluster --config tools/kind-config.yaml

# Bootstrap (push your branch first!)
git push -u origin HEAD
make dev
# or: python3 tools/setup.py
# or: python3 tools/setup.py --branch my-feature
```

### Prod bootstrap

```bash
python3 tools/setup.py --env prod
```

### What the script does

1. Installs ArgoCD via Helm chart.
2. Pre-applies bootstrap config (CNPG health check, OIDC, resource customizations).
3. Applies root ArgoCD Application (patched to current git branch for dev, `main` for prod).
4. ArgoCD takes over and syncs all resources via app-of-apps.

Key facts:

- Dev overlays hardcode `localhost`; base/prod overlays use `DOMAIN_PLACEHOLDER` for real domains.
- Developers must push their branch to GitHub before running `make dev` (ArgoCD syncs from remote).
- Keycloak is deployed as a plain Deployment + Service (no operator). Realm config is imported via a keycloak-config-cli PostSync Job.
- All applications (web, ArgoCD, server, mobile) authenticate directly with Keycloak via OIDC.
- Monitor sync progress: `make dev-status` or `kubectl get applications -n argocd`.

## Makefile

Use `make help` to see all available targets. Key targets:

- `make dev` - Bootstrap local dev environment.
- `make dev-status` - Show ArgoCD Application sync status.
- `make validate` - Verify all Kustomize overlays build cleanly.
- `make lint` - Run kubeconform schema validation.
- `make clean` - Delete the local KIND cluster.

## Kubernetes Handy Commands

```bash
kubectl get applications -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl port-forward -n spezistudyplatform svc/keycloak 8081:80
```

## Keycloak Notes

- Keycloak is deployed as a plain Deployment + Service in `infrastructure/base/keycloak/keycloak.yaml`.
- Realm configuration (clients, roles, scopes, test users) is managed by a keycloak-config-cli Job in `infrastructure/dev/keycloak-realm-import-job.yaml` (runs as ArgoCD PostSync hook).
- Client secrets are injected via ExternalSecrets from Vault into the Job's environment variables.
- For prod config enforcement, a keycloak-config-cli Job with ArgoCD PreSync hook exists in `infrastructure/prod/keycloak-config-cli-job.yaml`.

## Prerequisites for Contributors

Install: `kind`, `kubectl`, `helm`, and `python3`. Optional but useful: `k9s`, `direnv`, `kubeconform`.

## Code Style & Commits

- Follow repository formatting; all infrastructure is plain YAML (Kustomize overlays + Helm values).
- Commit messages stay boring/professional (no emojis or signatures).
- `tools/setup.py` bootstraps ArgoCD; ArgoCD is the source of truth for cluster state.
