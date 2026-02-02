# AGENTS.md

Guidance for AI coding assistants (Claude, ChatGPT, Gemini, etc.) contributing to this repository. Read this first so you can follow the conventions and tooling the rest of the team expects.

## Architecture Overview

The Spezi Study Platform uses a GitOps workflow where Argo CD continuously applies Jsonnet/Tanka configurations.

- `environments/`: Tanka environments (`local-dev`, `default`, `prod-bootstrap`, `argocd-bootstrap`).
- `lib/platform/`: Jsonnet libraries for platform components (auth, backend, networking, etc.).
- `tofu/`: OpenTofu/Terraform modules (GKE, Keycloak bootstrap, supporting services).
- `ansible/`: Playbooks for bootstrapping production prerequisites.
- `tools/spezi_setup/`: Python orchestration script that now drives both local and production workflows.
- `setup-local.sh` / `setup-prod.sh`: Legacy shell scripts kept for reference; prefer the Python entrypoint.

## Primary Automation (`tools/spezi_setup/spezi_setup.py`)

Run everything through the Python helper; it encapsulates the latest behavior that shell scripts lack.

### Local KIND environment
```bash
python3 tools/spezi_setup/spezi_setup.py local \
  --kind-cluster-name spezi-study-platform \
  --force-recreate-kind  # optional if you want to rebuild the cluster from scratch
```
Key facts:
- Creates/updates the KIND cluster, installs Argo CD, applies the Jsonnet root app, and bootstraps Keycloak via OpenTofu.
- Automatically syncs the oauth2-proxy secret from the bootstrap state.
- Prints the Argo CD admin password and port-forward instructions at the end (`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`).

### Production setup / teardown
```bash
python3 tools/spezi_setup/spezi_setup.py prod --action setup \
  --gcp-project-id spezi-studyplatform-dev \
  --production-domain platform.spezi.stanford.edu \
  --auto-approve  # optional, skip confirmation prompts

python3 tools/spezi_setup/spezi_setup.py prod --action teardown
```
Highlights:
- Handles gcloud auth, service-account activation, and populates `ansible/group_vars` with the credentials path.
- Bootstraps Keycloak using OpenTofu, waits for the realm, and then configures Argocd/OAuth apps.
- During teardown it enumerates state and targets everything except the reserved static IP (see `KNOWN_ISSUES.md` for alternatives we want to explore).
- Supports missing `admin-username` in the Keycloak secret by defaulting to `user`, matching the Bitnami chart behavior.
- If Keycloak does not return a client secret for the Argo CD client (because it is `PUBLIC`), the script logs a warning and skips syncing Secret Manager instead of failing.

## Legacy Commands (use only if explicitly told)
- `setup-local.sh` / `setup-prod.sh` mirror the Python logic but lack recent fixes.
- `tk apply environments/<env>` to apply specific Jsonnet environments manually.
- `tofu` modules live under `tofu/`; run from those directories if you need ad-hoc operations.

## Kubernetes Handy Commands
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl port-forward -n spezistudyplatform svc/keycloak 8081:80
```

## Deployment Waves
1. Namespaces, CRDs, cluster-scoped prerequisites.
2. Operators/controllers (CloudNative-PG, cert-manager, etc.).
3. Platform applications (Keycloak, backend, frontend, supporting services).

Wave definitions live in `tools/spezi_setup/spezi_setup.py` (see the `WaveSpec` usage around `handle_application_waves`).

## Keycloak Bootstrap Notes
- The Kubernetes secret `spezistudyplatform/keycloak` must contain `admin-password`; `admin-username` is optional because the automation defaults to `user` if absent.
- OAuth client secrets are fetched via the Keycloak admin API; missing secrets no longer abort the run.
- For local boots the script reads OpenTofu state from `tofu/keycloak-bootstrap/tf` using a `.terraform-local` directory to avoid polluting global state.

## Known Issues
Refer to `KNOWN_ISSUES.md` for up-to-date workarounds (e.g., broken Keycloak login to Argo CD, OpenTofu `-target` usage during teardown). Keep that file updated whenever you discover new limitations.

## Prerequisites for Contributors
Install: `kind`, `kubectl`, `tanka`, `jsonnet-bundler`, `opentofu` (or Terraform), `gcloud`, `ansible`, and `python3`. Optional but useful: `k9s`, `direnv`.

## Code Style & Commits
- Follow repository formatting; prefer Jsonnet/Tanka idioms already in use.
- Commit messages stay boring/professional (no emojis or signatures).
- When editing automation scripts, keep behavior parity between Python and any legacy shell counterparts when possible, if shell counterparts exist.
