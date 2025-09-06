# -----------------------------
# General / Region
# -----------------------------
variable "region" {
  description = "AWS region for EKS"
  type        = string
  default     = "eu-central-1"
}

# -----------------------------
# VPC
# -----------------------------
variable "vpc_id" {
  description = "VPC ID where EKS will be created"
  type        = string
  default     = "vpc-09539bf7c455d4246"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS worker nodes"
  type        = list(string)
  default     = ["subnet-0cb0686e33097c0e9", "subnet-0b663bd1771a08d88", "subnet-04e63728632af7300"]
}

# -----------------------------
# Cluster settings
# -----------------------------
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "hive-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.32"
}

# -----------------------------
# Optional managed node group (single)
# -----------------------------
variable "create_node_group" {
  description = "Whether to create a managed node group"
  type        = bool
  default     = true
}

variable "node_group_name" {
  description = "Managed node group name (used when create_node_group = true)"
  type        = string
  default     = "default"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t2.small"]
}

variable "node_capacity_type" {
  description = "Capacity type for the node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be either \"ON_DEMAND\" or \"SPOT\"."
  }
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 2
}

# -----------------------------
# Modern access (EKS Access Entries, no aws-auth)
# -----------------------------
variable "human_admin_role_arn" {
  description = "IAM Role ARN for human admin access (e.g., AWS SSO role)"
  type        = string
  default = "arn:aws:iam::959413831332:role/eks-human-admin"
}

variable "ci_role_arn" {
  description = "IAM Role ARN for CI/CD (GitHub OIDC) with limited access"
  type        = string
  default = "arn:aws:iam::959413831332:role/eks-ci-role"
}

# -----------------------------
# CI access scope/policy
# -----------------------------
variable "ci_namespaces" {
  description = "Namespaces that CI can access (namespace-scoped access)"
  type        = list(string)
  default     = ["greeter"]
}

variable "ci_access_policy_arn" {
  description = "Managed EKS access policy for CI (e.g., AmazonEKSEditPolicy)"
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
}

variable "ingress_allowed_cidrs" {
  description = "CIDR ranges allowed to reach ingress-nginx via NLB (use 0.0.0.0/0 for internet-facing; use VPC CIDR(s) for internal)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
