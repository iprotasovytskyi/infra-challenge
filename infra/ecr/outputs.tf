output "repository_url" {
  description = "Full repository URL (use it for docker login/push)"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "Repository ARN"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Repository name"
  value       = aws_ecr_repository.this.name
}