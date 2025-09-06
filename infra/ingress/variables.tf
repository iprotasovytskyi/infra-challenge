# ============================
# Ingress NGINX Helm variables
# ============================

variable "region" {
  description = "AWS region used by the AWS/Kubernetes/Helm providers."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "EKS cluster name to discover API endpoint and CA."
  type        = string
  default     = "hive-eks"
}

variable "human_admin_role_arn" {
  description = "IAM role ARN to assume for Kubernetes auth (should have EKS Access Entry, e.g. ClusterAdmin)."
  type        = string
  default     = "arn:aws:iam::959413831332:role/eks-human-admin"
}

variable "namespace" {
  description = "Kubernetes namespace for the ingress-nginx release."
  type        = string
  default     = "ingress-nginx"
}

variable "create_namespace" {
  description = "Whether to create the namespace for the Helm release."
  type        = bool
  default     = true
}

variable "chart_version" {
  description = "Pinned Helm chart version for ingress-nginx."
  type        = string
  default     = "4.12.1"
}

variable "lb_cidrs" {
  description = "CIDRs для відкриття на SG нод"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
