output "cluster_name" {
  description = "GKE cluster name (use to replace CLUSTER_NAME_TODO in cluster-secret-store.yaml)"
  value       = google_container_cluster.primary.name
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

    2. Replace CLUSTER_NAME_TODO in infrastructure/prod/cluster-secret-store.yaml:
       Cluster name: ${google_container_cluster.primary.name}

    3. Add loadBalancerIP to argocd-apps/prod/traefik-values.yaml:
       loadBalancerIP: "${google_compute_address.traefik.address}"

    4. Populate secrets in GCP Secret Manager:
       - server-db-credentials
       - keycloak-db-credentials
       - keycloak-admin-credentials
       - server-credentials

    5. Request DNS A record from Stanford IT:
       ${var.domain} -> ${google_compute_address.traefik.address}

    6. Commit manifest changes, push, then bootstrap:
       python3 tools/setup.py --env prod
  EOT
}
