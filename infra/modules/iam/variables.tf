variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

# ----- Human admin role (optional) -----
variable "create_human_admin_role" {
  description = "Create a human admin IAM role (cluster rights via EKS Access Entries)"
  type        = bool
  default     = true
}

variable "human_admin_role_name" {
  description = "IAM role name for the human admin"
  type        = string
  default     = "eks-human-admin"
}

variable "human_admin_trusted_principals" {
  description = "Principals (ARNs) allowed to assume the human admin role (SSO roles or IAM users)"
  type        = list(string)
  default     = []
}

# ----- CI role (GitHub OIDC) -----
variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider (only once per account)"
  type        = bool
  default     = true
}

variable "create_ci_role" {
  description = "Create a CI role trusted by GitHub OIDC"
  type        = bool
  default     = true
}

variable "ci_role_name" {
  description = "IAM role name for CI"
  type        = string
  default     = "eks-ci-role"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI role (format: owner/repo)"
  type        = string
}

variable "github_branch" {
  description = "Branch reference allowed to assume the CI role (e.g., main)"
  type        = string
  default     = "main"
}

# ----- Narrow CI permissions to a single ECR repo -----
variable "ecr_repo_name" {
  description = "ECR repository name that CI may push/pull"
  type        = string
  default     = "greeter"
}
