#
# This source file is part of the Stanford Spezi open source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "cluster_name" {
  description = "GKE cluster name (use to replace CLUSTER_NAME_TODO in cluster-secret-store.yaml)"
  value       = google_container_cluster.primary.name
}

output "cluster_zone" {
  description = "GKE cluster zone"
  value       = var.zone
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "traefik_static_ip" {
  description = "Static IP for Traefik LoadBalancer (set as DNS A record)"
  value       = google_compute_address.traefik.address
}

output "external_secrets_sa_email" {
  description = "GCP service account email for External Secrets Operator"
  value       = google_service_account.external_secrets.email
}

output "get_credentials_command" {
  description = "Run this to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.zone} --project ${var.project_id}"
}

output "post_apply_instructions" {
  description = "Manual steps after tofu apply"
  value       = <<-EOT

    Post-apply checklist:

    1. Get kubeconfig:
       $(tofu output -raw get_credentials_command)

    2. Verify loadBalancerIP in argocd-apps/prod/traefik-values.yaml matches: ${google_compute_address.traefik.address}
       (commit and push before bootstrapping)

    3. Add /etc/hosts entry:
       ${google_compute_address.traefik.address} ${var.domain}

    4. Bootstrap ArgoCD:
       make prod-bootstrap
  EOT
}
