output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_data" {
  description = "Base64 encoded CA data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

# Safe when node group is disabled: returns {}
output "node_group_role_arns" {
  description = "IAM role ARNs for all managed node groups (empty map if none)"
  value       = { for k, v in try(module.eks.eks_managed_node_groups, {}) : k => v.iam_role_arn }
}

output "cluster_security_group_id" {
  description = "Security group ID for the EKS control plane"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID for worker nodes"
  value       = module.eks.node_security_group_id
}
