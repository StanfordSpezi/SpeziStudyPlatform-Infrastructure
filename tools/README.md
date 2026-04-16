# Tools

Helper scripts for the local development environment.

## Contents

- `setup.py` - Bootstrap script. Installs ArgoCD via Helm, then applies the root Application. Used by `make dev`.
- `run_integration_tests.py` - Integration test runner.
- `kind-config.yaml` - KIND cluster configuration.
