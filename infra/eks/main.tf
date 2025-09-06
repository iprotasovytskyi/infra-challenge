terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws        = { source = "hashicorp/aws", version = ">= 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.23" }
    helm       = { source = "hashicorp/helm", version = ">= 2.13" }
  }

  backend "s3" {
    bucket         = "hivemind-tf-state" # <- your S3 bucket name from bootstrap
    key            = "eks/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tf-lock-hivemind-dev" # <- your DynamoDB table name from bootstrap
    encrypt        = true
    profile        = "hivemind"
  }
}

provider "aws" {
  region  = var.region
  profile = "hivemind"
}

# -----------------------------
# EKS cluster with IRSA + core managed add-ons
# -----------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Networking
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_additional_security_group_ids = ["sg-0be66e53a81508c88"]

  # OIDC provider for IRSA
  enable_irsa = true

  # Control-plane logs (helpful for troubleshooting)
  cluster_enabled_log_types = []

  # Core managed add-ons (EBS CSI is handled separately to bind IRSA role)
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # # Extra inbound rules for node shared security group (opens 80/443)
  # node_security_group_additional_rules = {
  #   ingress_nlb_http = {
  #     description = "Allow HTTP (80) from NLB/clients to nodes for ingress-nginx"
  #     protocol    = "tcp"
  #     from_port   = 80
  #     to_port     = 80
  #     type        = "ingress"
  #     cidr_blocks = var.ingress_allowed_cidrs
  #   }
  #   ingress_nlb_https = {
  #     description = "Allow HTTPS (443) from NLB/clients to nodes for ingress-nginx"
  #     protocol    = "tcp"
  #     from_port   = 443
  #     to_port     = 443
  #     type        = "ingress"
  #     cidr_blocks = var.ingress_allowed_cidrs
  #   }
  #   ingress_nlb_nodeports = {
  #     description = "Allow NLB to NodePorts for ingress-nginx"
  #     protocol    = "tcp"
  #     from_port   = 30000
  #     to_port     = 32767
  #     type        = "ingress"
  #     cidr_blocks = ["0.0.0.0/0"] # або обмеж свій діапазон/вихідні проксі
  #   }
  # }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      ecr_ro = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    }
  }

  # Optional single managed node group (empty map when create_node_group = false)
  eks_managed_node_groups = var.create_node_group ? {
    (var.node_group_name) = {
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      labels = { role = "worker" }
      taints = [] # add taints here if you need dedicated nodes
    }
  } : {}

  tags = {
    Project     = "hivemind-infra-challenge"
    Environment = "hivemind"
  }
}

# -----------------------------
# Providers to talk to the cluster (via EKS auth)
# -----------------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = module.eks.cluster_token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = module.eks.cluster_token
  }
}

# -----------------------------
# IRSA for EBS CSI (controller) + EBS CSI managed add-on
# -----------------------------
# AWS managed policy required by the EBS CSI controller
data "aws_iam_policy" "ebs_csi_managed" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Trust policy for ServiceAccount kube-system:ebs-csi-controller-sa
data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    # Bind to the controller SA
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    # Required audience for AWS STS
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_controller" {
  name               = "${var.cluster_name}-ebs-csi-controller"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
  tags = {
    ManagedBy = "terraform"
    Purpose   = "ebs-csi-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_attach" {
  role       = aws_iam_role.ebs_csi_controller.name
  policy_arn = data.aws_iam_policy.ebs_csi_managed.arn
}

# EBS CSI as a managed add-on with IRSA role bound
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi_controller.arn

  # NEW: explicit conflict resolution fields (replace deprecated resolve_conflicts)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # optional pin:
  addon_version = null

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.ebs_csi_attach
  ]
}


# -----------------------------
# Modern Access Entries (no aws-auth)
# -----------------------------
locals {
  human_admin_policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

# Human admin: cluster-wide admin
resource "aws_eks_access_entry" "human_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.human_admin_role_arn
  type          = "STANDARD"
  depends_on    = [module.eks]
  tags          = { ManagedBy = "terraform", Purpose = "human-admin" }
}

resource "aws_eks_access_policy_association" "human_admin_assoc" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.human_admin_role_arn
  policy_arn    = local.human_admin_policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.human_admin]
}

# CI: namespace-scoped access (default policy = AmazonEKSEditPolicy)
resource "aws_eks_access_entry" "ci" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.ci_role_arn
  type          = "STANDARD"
  depends_on    = [module.eks]
  tags          = { ManagedBy = "terraform", Purpose = "ci" }
}

resource "aws_eks_access_policy_association" "ci_assoc" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.ci_role_arn
  policy_arn    = var.ci_access_policy_arn

  access_scope {
    type       = "namespace"
    namespaces = var.ci_namespaces
  }

  depends_on = [aws_eks_access_entry.ci]
}
