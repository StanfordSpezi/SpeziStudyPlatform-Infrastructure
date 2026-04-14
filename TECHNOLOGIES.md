# Technologies

## Container & Orchestration
- **Kubernetes** (v1.29 API target)
- **KIND** (local clusters)
- **Docker** (container images)

## GitOps & Deployment
- **ArgoCD** (continuous deployment)
- **Tanka** (Jsonnet-based K8s config management)
- **Jsonnet** (data templating language)
- **Kustomize** (overlay-based K8s manifests)
- **Helm** (chart templating, used via Tanka's helm-util)

## Infrastructure as Code
- **OpenTofu** / **Terraform** (Keycloak bootstrap)

## Ingress & Networking
- **Traefik** v37.0.0 (ingress controller, IngressRoutes, middlewares)
- **nip.io** (wildcard DNS for local dev)

## Authentication & Authorization
- **Keycloak** v25.1.1 (OIDC identity provider)
- **OAuth2-Proxy** v8.0.2 (forward authentication)

## Database
- **CloudNative-PG** v1.27.0 (PostgreSQL operator)
- **PostgreSQL** (application database)

## Secrets & TLS
- **cert-manager** (TLS certificate lifecycle)
- **Let's Encrypt** (production TLS via ACME HTTP01)
- **External Secrets Operator** (syncs secrets from external stores)
- **HashiCorp Vault** (secrets backend, dev mode locally)

## Application Stack
- **ghcr.io/stanfordspezi/spezistudyplatform-server** (server)
- **ghcr.io/stanfordspezi/spezistudyplatform-web** (web SPA)

## Languages & Runtimes
- **Jsonnet** (infrastructure config)
- **Python 3** (setup orchestration, integration tests)
- **HCL** (OpenTofu/Terraform modules)
- **YAML** (Kubernetes manifests, Helm values)

## Dependency Management
- **jsonnet-bundler** (`jb`, manages Jsonnet vendor deps)
- **chartfile.yaml** (Helm chart vendoring)
- **Homebrew** (recommended tool installation)

## Jsonnet Vendor Libraries
- **ksonnet-util** (Grafana)
- **tanka-util** (Grafana)
- **helm-util** (Grafana)
- **k8s-libsonnet** v1.29 (jsonnet-libs)
- **docsonnet/doc-util** (jsonnet-libs)

## Observability & Dev Tools
- **k9s** (optional, terminal K8s UI)
- **kubectl** (cluster interaction)

## CI/CD & Storage
- **GHCR** (GitHub Container Registry for app images)
