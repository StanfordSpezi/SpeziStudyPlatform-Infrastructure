"""User-editable defaults for the Spezi setup utility.

Adjust the values in `LOCAL_DEFAULTS` or `PROD_DEFAULTS` to change the
argument defaults without modifying `spezi_setup.py`.
"""

from __future__ import annotations

LOCAL_DEFAULTS: dict[str, object | None] = {
    "kind_cluster_name": "spezi-study-platform",
    "force_recreate_kind": False,
    "local_ip": None,  # auto-detect via helper script when left as None
    "gcp_project_id": None,  # falls back to env vars or "local-dev"
}

PROD_DEFAULTS: dict[str, object | None] = {
    "action": "setup",
    "gcp_project_id": "spezistudyplatform-dev",
    "production_domain": "platform.spezi.stanford.edu",
    "static_ip": "34.168.138.135",
    "tf_state_bucket": "spezistudyplatform-tf-state-prod",
    "tf_state_prefix": "terraform/state/keycloak-bootstrap",
    "gke_tf_state_prefix": "gke/spezistudyplatform",
    "service_account_email": None,
    # None here means it will load from the default place (./gcp-service-account-key.json)
    "credentials_file": None,
    "keycloak_realm": "spezistudyplatform",
    # note, this base_url is only used to configure keycloak itself at bootstrap time
    "keycloak_base_url": "http://localhost:8081/auth",
    # None here means it will be auto-generated during setup.
    "keycloak_admin_username": None,
    "keycloak_admin_password": None,
    "auto_approve": False,
}
