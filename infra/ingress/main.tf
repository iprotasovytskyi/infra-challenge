terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"
    }
  }

  backend "s3" {
    bucket         = "hivemind-tf-state" # <- your S3 bucket name from bootstrap
    key            = "ingress/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tf-lock-hivemind-dev" # <- your DynamoDB table name from bootstrap
    encrypt        = true
    profile        = "hivemind"
  }
}

provider "aws" {
  region  = var.region
  profile = "hivemind"
  assume_role {
    role_arn     = var.human_admin_role_arn
    session_name = "tf-eks-admin"
  }
}

# Discover cluster connection details
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# Generate token for k8s/helm providers
data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

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

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket         = "hivemind-tf-state"       # той самий bucket, що в EKS
    key            = "eks/terraform.tfstate"   # шлях до state EKS
    region         = "eu-central-1"
    dynamodb_table = "tf-lock-hivemind-dev"
    encrypt        = true
    profile        = "hivemind"
  }
}

# Use release name "public-ingress" to match your selectors in values.yaml
resource "helm_release" "ingress_nginx" {
  name             = "public-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.chart_version

  namespace        = var.namespace
  create_namespace = var.create_namespace

  # Take ALL settings from your values.yaml
  values = [file("${path.module}/public-ingress.yaml"),]
}

# Optional: expose NLB DNS name (controller Service is <release>-controller)
data "kubernetes_service" "controller" {
  metadata {
    name      = "${helm_release.ingress_nginx.name}-controller"
    namespace = var.namespace
  }
  depends_on = [helm_release.ingress_nginx]
}
