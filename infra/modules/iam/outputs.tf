output "human_admin_role_arn" {
  description = "ARN of the created human admin role (null if not created)"
  value       = try(aws_iam_role.human_admin[0].arn, null)
}

output "ci_role_arn" {
  description = "ARN of the created CI role (null if not created)"
  value       = try(aws_iam_role.ci[0].arn, null)
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (null if not created)"
  value       = try(aws_iam_openid_connect_provider.github[0].arn, null)
}
