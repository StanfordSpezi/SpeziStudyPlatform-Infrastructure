resource "keycloak_realm" "realm" {
  realm   = "spezistudyplatform"
  enabled = true
  # Note: frontend_url configuration needs to be set at Keycloak server level
  # through KEYCLOAK_FRONTEND_URL environment variable

  # Set SSO session timeout to 24 hours (86400 seconds)
  sso_session_idle_timeout = "24h"
  sso_session_max_lifespan = "24h"
}


# configured per: https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/keycloak_oidc 
resource "keycloak_openid_client" "oauth2_proxy_client" {
  realm_id  = keycloak_realm.realm.id
  client_id = "oauth2-proxy"

  name    = "oauth2-proxy"
  enabled = true

  access_type = "CONFIDENTIAL"
  valid_redirect_uris = [
    "${var.web_url}/oauth2/callback"
  ]

  client_secret                = random_password.oauth2_proxy_client_secret.result
  direct_access_grants_enabled = false
  standard_flow_enabled        = true

  depends_on = [random_password.oauth2_proxy_client_secret]
}

# Create groups client scope
resource "keycloak_openid_client_scope" "groups_scope" {
  realm_id    = keycloak_realm.realm.id
  name        = "groups"
  description = "Groups membership"
}

# Add groups scope mapper for OAuth2-proxy
locals {
  oauth2_proxy_groups_mapper_id = "404c6487-938b-4a7e-9457-5d67f8deebf8"
  oauth2_proxy_roles_mapper_id  = "db618d00-2a62-49e7-a57f-d372c87b2520"
  argocd_groups_mapper_id       = "63bf4638-17d6-4b5c-8910-c0c508b5db5d"
  argocd_roles_mapper_id        = "2b2e210b-c677-42ac-89d9-31162119b0eb"
}

resource "keycloak_openid_group_membership_protocol_mapper" "oauth2_proxy_groups_mapper" {
  count           = local.oauth2_proxy_groups_mapper_id == "" ? 1 : 0
  realm_id        = keycloak_realm.realm.id
  client_scope_id = keycloak_openid_client_scope.groups_scope.id
  name            = "groups"

  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Add roles mapper to groups scope (OAuth2-proxy checks roles in groups claim)
resource "keycloak_openid_user_realm_role_protocol_mapper" "oauth2_proxy_roles_mapper" {
  count           = local.oauth2_proxy_roles_mapper_id == "" ? 1 : 0
  realm_id        = keycloak_realm.realm.id
  client_scope_id = keycloak_openid_client_scope.groups_scope.id
  name            = "realm roles"

  claim_name          = "groups"
  multivalued         = true
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Assign groups scope to oauth2-proxy client and retain built-in optional scopes
resource "keycloak_openid_client_optional_scopes" "oauth2_proxy_optional_scopes" {
  realm_id  = keycloak_realm.realm.id
  client_id = keycloak_openid_client.oauth2_proxy_client.id
  optional_scopes = [
    keycloak_openid_client_scope.groups_scope.name,
    "address",
    "microprofile-jwt",
    "offline_access",
    "phone",
  ]
}

# Create required role for OAuth2-proxy authorization
resource "keycloak_role" "authorized_users" {
  realm_id    = keycloak_realm.realm.id
  name        = "spezistudyplatform-authorized-users"
  description = "Users authorized to access the Spezi Study Platform"
}

# Create ArgoCD admin role so we can share it across users
resource "keycloak_role" "argocd_admins" {
  realm_id    = keycloak_realm.realm.id
  name        = "ArgoCDAdmins"
  description = "ArgoCD Administrators"
}

# Note: User creation for production should be done through proper user management processes
# The following users are examples for local development only and should not be deployed to production

# Test user 1 - authorized user
resource "keycloak_user" "testuser" {
  count          = var.create_test_users ? 1 : 0
  realm_id       = keycloak_realm.realm.id
  username       = "testuser"
  email          = "testuser@example.com"
  email_verified = true

  first_name = "Test"
  last_name  = "User"

  initial_password {
    value     = "password123"
    temporary = false
  }
}

# Test user 2 - unauthorized user  
resource "keycloak_user" "testuser2" {
  count          = var.create_test_users ? 1 : 0
  realm_id       = keycloak_realm.realm.id
  username       = "testuser2"
  email          = "testuser2@example.com"
  email_verified = true

  first_name = "Test"
  last_name  = "User2"

  initial_password {
    value     = "password456"
    temporary = false
  }
}

# Assign Spezi and ArgoCD roles to testuser for local dev convenience
resource "keycloak_user_roles" "testuser_roles" {
  count    = var.create_test_users ? 1 : 0
  realm_id = keycloak_realm.realm.id
  user_id  = keycloak_user.testuser[count.index].id

  role_ids = [
    keycloak_role.authorized_users.id,
    keycloak_role.argocd_admins.id
  ]
}

# Note: testuser2 intentionally does not get the authorized role

resource "keycloak_user" "newadmin" {
  count          = var.create_test_users ? 1 : 0
  realm_id       = keycloak_realm.realm.id
  username       = "newadmin"
  email          = "newadmin@example.com"
  email_verified = true

  first_name = "New"
  last_name  = "Admin"

  initial_password {
    value     = "password"
    temporary = false
  }
}



# ArgoCD OIDC Client Configuration (supports both web UI and CLI)
resource "keycloak_openid_client" "argocd_client" {
  realm_id  = keycloak_realm.realm.id
  client_id = "argocd"

  name    = "ArgoCD"
  enabled = true

  access_type = "PUBLIC"
  valid_redirect_uris = [
    "${var.web_url}/argo/auth/callback",
    "${var.web_url}/argo/auth/login",
    "http://localhost:8085/auth/callback"
  ]

  # Enable PKCE for CLI support
  pkce_code_challenge_method = "S256"

  direct_access_grants_enabled = false
  standard_flow_enabled        = true
}

# Add groups mapper to standard groups scope for ArgoCD
resource "keycloak_openid_group_membership_protocol_mapper" "argocd_groups_mapper" {
  count           = local.argocd_groups_mapper_id == "" ? 1 : 0
  realm_id        = keycloak_realm.realm.id
  client_scope_id = keycloak_openid_client_scope.groups_scope.id
  name            = "argocd-groups"

  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Add roles mapper to groups scope for ArgoCD
resource "keycloak_openid_user_realm_role_protocol_mapper" "argocd_roles_mapper" {
  count           = local.argocd_roles_mapper_id == "" ? 1 : 0
  realm_id        = keycloak_realm.realm.id
  client_scope_id = keycloak_openid_client_scope.groups_scope.id
  name            = "argocd-realm-roles"

  claim_name          = "groups"
  multivalued         = true
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Assign groups scope to ArgoCD client and retain built-in optional scopes
resource "keycloak_openid_client_optional_scopes" "argocd_optional_scopes" {
  realm_id  = keycloak_realm.realm.id
  client_id = keycloak_openid_client.argocd_client.id
  optional_scopes = [
    keycloak_openid_client_scope.groups_scope.name,
    "address",
    "microprofile-jwt",
    "offline_access",
    "phone",
  ]
}

resource "random_password" "oauth2_proxy_client_secret" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}


resource "kubernetes_secret" "oauth2_proxy_secret_update" {
  count = var.enable_vault_secret_sync ? 1 : 0

  metadata {
    name      = "oauth2-proxy-secret-update"
    namespace = "vault"
  }

  data = {
    "client-secret" = random_password.oauth2_proxy_client_secret.result
  }

  type = "Opaque"

  depends_on = [random_password.oauth2_proxy_client_secret]
}

# Web SPA client (public, PKCE), used by keycloak-js in spezistudyplatform-web
resource "keycloak_openid_client" "web_client" {
  realm_id  = keycloak_realm.realm.id
  client_id = "spezistudyplatform-web"
  name      = "Spezi Study Platform Web"
  enabled   = true

  access_type                  = "PUBLIC"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris = [
    "${var.web_url}/*",
  ]
  web_origins = [
    var.web_url,
  ]
}

# The Vapor server's KeycloakJWTPayload expects realm roles at a top-level
# `roles` claim. Keycloak's default puts them under `realm_access.roles`,
# so emit a flat `roles` claim into access tokens issued for the SPA client.
resource "keycloak_openid_user_realm_role_protocol_mapper" "web_roles_mapper" {
  realm_id  = keycloak_realm.realm.id
  client_id = keycloak_openid_client.web_client.id
  name      = "realm roles -> roles"

  claim_name          = "roles"
  multivalued         = true
  claim_value_type    = "String"
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Server client (confidential, service accounts for client credentials flow)
resource "keycloak_openid_client" "server_client" {
  realm_id                     = keycloak_realm.realm.id
  client_id                    = "spezistudyplatform-server"
  name                         = "Spezi Study Platform Server"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  client_secret                = "change-me-in-production"
  service_accounts_enabled     = true
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
}

# Realm roles checked by AuthMiddleware when validating JWTs
resource "keycloak_role" "researcher_role" {
  realm_id    = keycloak_realm.realm.id
  name        = "spezistudyplatform-researcher"
  description = "Researchers authorized to manage studies"
}

resource "keycloak_role" "participant_role" {
  realm_id    = keycloak_realm.realm.id
  name        = "spezistudyplatform-participant"
  description = "Participants in Spezi studies via mobile app"
}

# Service account role bindings, server calls GET /admin/realms/{realm}/groups on startup
data "keycloak_openid_client" "realm_management" {
  realm_id  = keycloak_realm.realm.id
  client_id = "realm-management"
}

resource "keycloak_openid_client_service_account_role" "server_view_users" {
  realm_id                = keycloak_realm.realm.id
  service_account_user_id = keycloak_openid_client.server_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management.id
  role                    = "view-users"
}

resource "keycloak_openid_client_service_account_role" "server_query_groups" {
  realm_id                = keycloak_realm.realm.id
  service_account_user_id = keycloak_openid_client.server_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management.id
  role                    = "query-groups"
}

resource "kubernetes_job_v1" "vault_oauth2_proxy_secret_update" {
  count = var.enable_vault_secret_sync ? 1 : 0

  metadata {
    name      = "vault-oauth2-proxy-secret-update"
    namespace = "vault"
  }

  spec {
    template {
      metadata {}
      spec {
        restart_policy = "Never"
        container {
          name  = "vault-update"
          image = "hashicorp/vault:1.15"
          command = [
            "sh",
            "-c",
            "CLIENT_SECRET=$(cat /secret/client-secret) && vault kv put secret/oauth2-proxy-secret client-id=oauth2-proxy client-secret=$CLIENT_SECRET cookie-secret=local-dev-cookie-secret-32-chars"
          ]
          env {
            name  = "VAULT_ADDR"
            value = "http://vault.vault.svc.cluster.local:8200"
          }
          env {
            name  = "VAULT_TOKEN"
            value = "dev-only-token"
          }
          volume_mount {
            name       = "secret-volume"
            mount_path = "/secret"
            read_only  = true
          }
        }
        volume {
          name = "secret-volume"
          secret {
            secret_name = kubernetes_secret.oauth2_proxy_secret_update[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_secret.oauth2_proxy_secret_update]
}
