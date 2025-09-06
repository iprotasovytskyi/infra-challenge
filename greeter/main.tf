terraform {
  required_providers {
    aws         = { source = "hashicorp/aws", version = ">= 5.0" }
    kubernetes  = { source = "hashicorp/kubernetes", version = "~> 2.29" }
    helm        = { source = "hashicorp/helm", version = "~> 2.12" }
  }
  backend "s3" {
    bucket         = "hivemind-tf-state"
    key            = "greeter/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tf-lock-hivemind-dev"
    encrypt        = true
    profile        = "hivemind"
  }
}

# AWS & cluster targeting
variable "region" {
  description = "AWS region to operate in"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Target EKS cluster name"
  type        = string
  default     = "hive-eks"
}

# Release / namespace
variable "namespace" {
  description = "Kubernetes namespace to install the Helm release into"
  type        = string
  default     = "greeter"
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "greeter"
}

# Container image (ECR)
variable "image_repository" {
  description = "Full image repository (ECR), e.g. <ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/greeter"
  type        = string
  default = "959413831332.dkr.ecr.eu-central-1.amazonaws.com/greeter"
}

variable "image_tag" {
  description = "Image tag to deploy"
  type        = string
  default     = "latest"
}

# Application configuration
variable "hello_tag" {
  description = "Value for HELLO_TAG environment variable passed to the app"
  type        = string
  default     = "dev"
}

variable "human_admin_role_arn" {
  description = "IAM role ARN to assume for Kubernetes auth (should have EKS Access Entry, e.g. ClusterAdmin)."
  type        = string
  default     = "arn:aws:iam::959413831332:role/eks-human-admin"
}

provider "aws" {
  region  = var.region
  profile = "hivemind"
  assume_role {
    role_arn     = var.human_admin_role_arn
    session_name = "tf-eks-admin"
  }
}

data "aws_eks_cluster" "this" { name = var.cluster_name }
data "aws_eks_cluster_auth" "this" { name = var.cluster_name }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

resource "helm_release" "greeter" {
  name             = var.release_name
  chart            = "${path.module}./chart"
  namespace        = var.namespace
  create_namespace = true

  set {
    name  = "image.repository"
    value = var.image_repository
  }
  set {
    name  = "image.tag"
    value = var.image_tag
  }
  set {
    name  = "env.HELLO_TAG"
    value = var.hello_tag
  }
}

output "ingress_hostname_hint" {
  description = "If host is empty in values.yaml, use the NLB hostname from the ingress-nginx controller Service"
  value       = "Check kube-system svc/public-ingress-controller EXTERNAL-IP"
}