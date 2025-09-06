terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" {
  region  = var.region
  profile = "hivemind"
}

data "aws_caller_identity" "current" {}

# ----------------------------------------------------
# GitHub OIDC identity provider (create once per account)
# ----------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  # GitHub's OIDC issuer
  url = "https://token.actions.githubusercontent.com"

  # Current GitHub OIDC thumbprint; update if GitHub changes it
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  # OIDC audience for AWS STS
  client_id_list = ["sts.amazonaws.com"]
}

# ----------------------------------------------------
# Human admin role (minimal AWS perms; cluster rights via EKS Access Entries)
# ----------------------------------------------------
data "aws_iam_policy_document" "human_admin_assume" {
  count = var.create_human_admin_role ? 1 : 0

  statement {
    sid     = "AllowAssume"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.human_admin_trusted_principals
    }
  }
}

resource "aws_iam_role" "human_admin" {
  count              = var.create_human_admin_role ? 1 : 0
  name               = var.human_admin_role_name
  assume_role_policy = data.aws_iam_policy_document.human_admin_assume[0].json

  tags = {
    ManagedBy = "terraform"
    Purpose   = "eks-human-admin"
  }
}

# Minimal AWS permissions: get EKS token and reach API; cluster-level rights come from Access Entries
data "aws_iam_policy_document" "human_admin_policy_doc" {
  count = var.create_human_admin_role ? 1 : 0

  statement {
    sid       = "EKSBasicAccess"
    actions   = ["eks:DescribeCluster", "eks:AccessKubernetesApi"]
    resources = ["*"]
  }
  statement {
    sid = "ReadSecurityGroups"
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules"
    ]
    resources = ["*"]
  }

  statement {
    sid = "ModifyAnySecurityGroup"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress"
    ]
    resources = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:security-group/*"]
  }
}

resource "aws_iam_policy" "human_admin_policy" {
  count       = var.create_human_admin_role ? 1 : 0
  name        = "eks-human-admin-basic"
  description = "Minimal AWS permissions for human EKS access; Kubernetes rights via EKS Access Entries"
  policy      = data.aws_iam_policy_document.human_admin_policy_doc[0].json
}

resource "aws_iam_role_policy_attachment" "human_admin_attach" {
  count      = var.create_human_admin_role ? 1 : 0
  role       = aws_iam_role.human_admin[0].name
  policy_arn = aws_iam_policy.human_admin_policy[0].arn
}

# allow modifying any Security Group (needed to open 80/443 on node SG for NLB)
resource "aws_iam_policy" "human_admin_sg_modify" {
  count       = var.create_human_admin_role ? 1 : 0
  name        = "eks-human-admin-sg-modify"
  description = "Allow modifying any Security Group ingress/egress in the account/region (for EKS LB access)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ModifyAnySecurityGroup"
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules"
        ]
        Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:security-group/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "human_admin_sg_modify_attach" {
  count      = var.create_human_admin_role ? 1 : 0
  role       = aws_iam_role.human_admin[0].name
  policy_arn = aws_iam_policy.human_admin_sg_modify[0].arn
}

# ----------------------------------------------------
# CI role (GitHub OIDC trust) + minimal ECR/EKS permissions
# ----------------------------------------------------
# Build GitHub OIDC provider ARN (use created resource if any, else assume it exists)
locals {
  github_oidc_provider_arn = try(
    aws_iam_openid_connect_provider.github[0].arn,
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
  )
}

data "aws_iam_policy_document" "ci_assume" {
  count = var.create_ci_role ? 1 : 0

  statement {
    sid     = "AllowGithubOIDC"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    # OIDC audience must be sts.amazonaws.com
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to a specific repo and branch
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "ci" {
  count              = var.create_ci_role ? 1 : 0
  name               = var.ci_role_name
  assume_role_policy = data.aws_iam_policy_document.ci_assume[0].json

  tags = {
    ManagedBy = "terraform"
    Purpose   = "eks-ci"
  }
}

# Minimal AWS permissions to reach the EKS API (Kubernetes rights via Access Entries)
data "aws_iam_policy_document" "ci_eks" {
  count = var.create_ci_role ? 1 : 0

  statement {
    sid       = "EKSBasicAccess"
    actions   = ["eks:DescribeCluster", "eks:AccessKubernetesApi"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_eks_policy" {
  count       = var.create_ci_role ? 1 : 0
  name        = "eks-ci-eks-basic"
  description = "CI minimal AWS permissions to access EKS API; RBAC via Access Entries"
  policy      = data.aws_iam_policy_document.ci_eks[0].json
}

resource "aws_iam_role_policy_attachment" "ci_eks_attach" {
  count      = var.create_ci_role ? 1 : 0
  role       = aws_iam_role.ci[0].name
  policy_arn = aws_iam_policy.ci_eks_policy[0].arn
}

# --- S3 backend (Terraform state) ---
data "aws_iam_policy_document" "ci_s3_backend" {
  statement {
    sid     = "ListStateBucket"
    actions = ["s3:ListBucket"]
    resources = [
      "arn:aws:s3:::hivemind-tf-state"
    ]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["greeter/*", "greeter/terraform.tfstate"]
    }
  }

  statement {
    sid = "RWStateObject"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::hivemind-tf-state/greeter/terraform.tfstate",
      "arn:aws:s3:::hivemind-tf-state/greeter/*"
    ]
  }
}

resource "aws_iam_policy" "ci_s3_backend" {
  name        = "eks-ci-s3-backend"
  description = "RW access to Terraform state in S3 (greeter/*)"
  policy      = data.aws_iam_policy_document.ci_s3_backend.json
}

resource "aws_iam_role_policy_attachment" "ci_s3_backend_attach" {
  role       = aws_iam_role.ci[0].name
  policy_arn = aws_iam_policy.ci_s3_backend.arn
}

# --- DynamoDB state lock ---
data "aws_iam_policy_document" "ci_dynamodb_lock" {
  statement {
    sid = "StateLockRW"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem"
    ]
    resources = [
      "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/tf-lock-hivemind-dev"
    ]
  }
}

resource "aws_iam_policy" "ci_dynamodb_lock" {
  name        = "eks-ci-dynamodb-lock"
  description = "Access to Terraform lock table"
  policy      = data.aws_iam_policy_document.ci_dynamodb_lock.json
}

resource "aws_iam_role_policy_attachment" "ci_dynamodb_lock_attach" {
  role       = aws_iam_role.ci[0].name
  policy_arn = aws_iam_policy.ci_dynamodb_lock.arn
}


# --- ECR push/pull (ALL repos) ---
data "aws_iam_policy_document" "ci_ecr_all" {
  statement {
    sid       = "ECRGetAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRRepoRWAll"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage"
    ]
    resources = [
      "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"
    ]
  }
}

resource "aws_iam_policy" "ci_ecr_all" {
  name        = "eks-ci-ecr-all-repos"
  description = "Push/pull to all ECR repositories in the account"
  policy      = data.aws_iam_policy_document.ci_ecr_all.json
}

resource "aws_iam_role_policy_attachment" "ci_ecr_all_attach" {
  role       = aws_iam_role.ci[0].name
  policy_arn = aws_iam_policy.ci_ecr_all.arn
}

# --- EKS API (helm/kubectl) ---
data "aws_iam_policy_document" "ci_eks_basic" {
  statement {
    sid       = "EKSBasicAccess"
    actions   = ["eks:DescribeCluster", "eks:AccessKubernetesApi"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_eks_basic" {
  name        = "eks-ci-eks-basic-ecr"
  description = "Access to EKS API; cluster RBAC controls actual perms"
  policy      = data.aws_iam_policy_document.ci_eks_basic.json
}

resource "aws_iam_role_policy_attachment" "ci_eks_basic_attach" {
  role       = aws_iam_role.ci[0].name
  policy_arn = aws_iam_policy.ci_eks_basic.arn
}
