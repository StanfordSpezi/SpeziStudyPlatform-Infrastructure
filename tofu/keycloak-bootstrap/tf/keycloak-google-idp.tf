# Keycloak Google Identity Provider Configuration

locals {
  google_client_id     = trimspace(var.google_oauth_client_id)
  google_client_secret = trimspace(var.google_oauth_client_secret)
  google_idp_enabled   = local.google_client_id != "" && local.google_client_secret != ""
}

# Google Identity Provider for Keycloak (optional)
resource "keycloak_oidc_identity_provider" "google" {
  count         = local.google_idp_enabled ? 1 : 0
  realm         = keycloak_realm.realm.id
  alias         = "google"
  display_name  = "Google"
  provider_id   = "google"
  client_id     = local.google_client_id
  client_secret = local.google_client_secret

  authorization_url = "https://accounts.google.com/oauth2/v2/auth"
  token_url         = "https://oauth2.googleapis.com/token"
  user_info_url     = "https://openidconnect.googleapis.com/v1/userinfo"
  jwks_url          = "https://www.googleapis.com/oauth2/v3/certs"
  issuer            = "https://accounts.google.com"

  # Enable automatic account creation
  store_token                   = false
  add_read_token_role_on_create = false
  authenticate_by_default       = false
  enabled                       = true
  trust_email                   = true
  link_only                     = false

  # Default scopes for Google
  default_scopes = "openid email profile"

  # Import existing user if email matches
  first_broker_login_flow_alias = "first broker login"
  sync_mode                     = "IMPORT"
}

# Identity Provider Mapper for email
locals {
  google_idp_mappers = {
    "email-mapper"          = "47fd1684-d95f-42a5-b0d2-db6fafc1475a"
    "first-name-mapper"     = "ec3e5137-9aea-489b-ba34-516d0acc92fc"
    "last-name-mapper"      = "64c79ba8-648c-42d2-a396-439bf04aaa1b"
    "username-mapper"       = "9568ff67-b6bd-472b-9747-1d599e536652"
    "email-verified-mapper" = "0ec84edd-68fc-4ce7-843e-ec6df04b9c11"
  }
}

resource "keycloak_custom_identity_provider_mapper" "google_email_mapper" {
  count                    = local.google_idp_enabled && local.google_idp_mappers["email-mapper"] == "" ? 1 : 0
  realm                    = keycloak_realm.realm.id
  name                     = "email-mapper"
  identity_provider_alias  = "google"
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"
  depends_on               = [keycloak_oidc_identity_provider.google]

  extra_config = {
    "syncMode"       = "INHERIT"
    "user.attribute" = "email"
    "claim"          = "email"
  }
}

# Identity Provider Mapper for first name
resource "keycloak_custom_identity_provider_mapper" "google_first_name_mapper" {
  count                    = local.google_idp_enabled && local.google_idp_mappers["first-name-mapper"] == "" ? 1 : 0
  realm                    = keycloak_realm.realm.id
  name                     = "first-name-mapper"
  identity_provider_alias  = "google"
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"
  depends_on               = [keycloak_oidc_identity_provider.google]

  extra_config = {
    "syncMode"       = "INHERIT"
    "user.attribute" = "firstName"
    "claim"          = "given_name"
  }
}

# Identity Provider Mapper for last name
resource "keycloak_custom_identity_provider_mapper" "google_last_name_mapper" {
  count                    = local.google_idp_enabled && local.google_idp_mappers["last-name-mapper"] == "" ? 1 : 0
  realm                    = keycloak_realm.realm.id
  name                     = "last-name-mapper"
  identity_provider_alias  = "google"
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"
  depends_on               = [keycloak_oidc_identity_provider.google]

  extra_config = {
    "syncMode"       = "INHERIT"
    "user.attribute" = "lastName"
    "claim"          = "family_name"
  }
}

# Identity Provider Mapper for username (use email as username)
resource "keycloak_custom_identity_provider_mapper" "google_username_mapper" {
  count                    = local.google_idp_enabled && local.google_idp_mappers["username-mapper"] == "" ? 1 : 0
  realm                    = keycloak_realm.realm.id
  name                     = "username-mapper"
  identity_provider_alias  = "google"
  identity_provider_mapper = "oidc-username-idp-mapper"
  depends_on               = [keycloak_oidc_identity_provider.google]

  extra_config = {
    "syncMode" = "INHERIT"
    "template" = "$${CLAIM.email}"
  }
}

# Identity Provider Mapper for email_verified (maps provider claim into Keycloak user.emailVerified)
resource "keycloak_custom_identity_provider_mapper" "google_email_verified_mapper" {
  count                    = local.google_idp_enabled && local.google_idp_mappers["email-verified-mapper"] == "" ? 1 : 0
  realm                    = keycloak_realm.realm.id
  name                     = "email-verified-mapper"
  identity_provider_alias  = "google"
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"
  depends_on               = [keycloak_oidc_identity_provider.google]

  extra_config = {
    "syncMode" = "INHERIT"
    # Map the OIDC claim 'email_verified' from Google into the Keycloak user property
    "user.attribute" = "emailVerified"
    "claim"          = "email_verified"
  }
}
