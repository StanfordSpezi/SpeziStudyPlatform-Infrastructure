# currently requires manual setup: https://registry.terraform.io/providers/mrparkers/keycloak/latest/docs
provider "kubernetes" {
  config_path = pathexpand(var.kube_config_path)
}

provider "keycloak" {
  client_id                = var.keycloak_client_id
  username                 = var.keycloak_username
  password                 = var.keycloak_password
  url                      = var.keycloak_url
  tls_insecure_skip_verify = true
}

terraform {
  required_providers {
    keycloak = {
      source  = "registry.terraform.io/mrparkers/keycloak"
      version = ">= 4.0.0"
    }
    random = {
      source  = "registry.terraform.io/hashicorp/random"
      version = ">= 3.1.0"
    }
    kubernetes = {
      source  = "registry.terraform.io/hashicorp/kubernetes"
      version = ">= 2.11.0"
    }
  }
}
