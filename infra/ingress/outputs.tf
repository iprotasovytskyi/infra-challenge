output "namespace" {
  value       = var.namespace
  description = "Namespace of ingress-nginx"
}

output "release_name" {
  value       = helm_release.ingress_nginx.name
  description = "Helm release name"
}

