variable "region" {
  description = "AWS region, e.g. eu-central-1"
  type        = string
  default = "eu-central-1"
}

variable "repo_name" {
  description = "ECR repository name (e.g., greeter)"
  type        = string
  default = "greeter"
}

variable "environment" {
  description = "Tag value for Environment"
  type        = string
  default     = "hivemind"
}

variable "force_delete" {
  description = "If true, allow deleting repo with images (useful for dev)"
  type        = bool
  default     = false
}

variable "enable_lifecycle" {
  description = "Enable a simple lifecycle rule for untagged images"
  type        = bool
  default     = true
}

variable "untagged_retention_days" {
  description = "Expire untagged images after N days"
  type        = number
  default     = 7
}

variable "attach_readonly_to_node_role" {
  description = "Attach AmazonEC2ContainerRegistryReadOnly to the provided node IAM role"
  type        = bool
  default     = false
}

variable "node_role_name" {
  description = "EKS node IAM role name (not ARN). Leave empty to skip attach"
  type        = string
  default     = ""
}