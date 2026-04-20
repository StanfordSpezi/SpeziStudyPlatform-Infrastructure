locals {
  secrets = {
    "server-db-credentials" = {
      placeholder = jsonencode({ username = "CHANGE_ME", password = "CHANGE_ME" })
    }
    "keycloak-db-credentials" = {
      placeholder = jsonencode({ username = "CHANGE_ME", password = "CHANGE_ME" })
    }
    "keycloak-admin-credentials" = {
      placeholder = jsonencode({ username = "CHANGE_ME", password = "CHANGE_ME" })
    }
    "server-credentials" = {
      placeholder = jsonencode({ KEYCLOAK_CLIENT_SECRET = "CHANGE_ME" })
    }
  }
}

resource "google_secret_manager_secret" "secrets" {
  for_each = local.secrets

  secret_id = each.key
  project   = var.project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

# Seed each secret with a placeholder so ESO does not fail on first sync.
# After apply, replace these values via the GCP console or gcloud CLI.
resource "google_secret_manager_secret_version" "initial" {
  for_each = local.secrets

  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = each.value.placeholder

  lifecycle {
    ignore_changes = [secret_data]
  }
}
