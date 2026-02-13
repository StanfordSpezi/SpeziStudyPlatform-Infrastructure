variable "keycloak_client_id" {
  description = "Keycloak client ID"
  type        = string
  default     = "admin-cli"
}

variable "keycloak_username" {
  description = "Keycloak username"
  type        = string
  default     = "user"
}

variable "keycloak_password" {
  description = "Keycloak password"
  type        = string
  sensitive   = true
}

variable "keycloak_url" {
  description = "Keycloak base URL"
  type        = string
  default     = "https://platform.spezi.stanford.edu/auth"
}

variable "frontend_url" {
  description = "Frontend URL for OAuth2 redirect URIs"
  type        = string
  default     = "https://spezi.172.20.117.44.nip.io" # Default to local-dev
}

variable "gcp_project_id" {
  description = "GCP project ID for OAuth client creation"
  type        = string
}

variable "enable_google_sso" {
  description = "Whether to fetch Google SSO credentials from Google Secret Manager"
  type        = bool
  default     = false
}

variable "google_oauth_client_id" {
  description = "Google OAuth client ID"
  type        = string
  default     = ""
}

variable "google_oauth_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_vault_secret_sync" {
  description = "Whether to push oauth2-proxy secrets into Vault via Kubernetes jobs"
  type        = bool
  default     = false
}

variable "create_test_users" {
  description = "Whether to provision example Keycloak users"
  type        = bool
  default     = false
}

variable "kube_config_path" {
  description = "Path to the kubeconfig file used by the Kubernetes provider"
  type        = string
  default     = "~/.kube/config"
}
