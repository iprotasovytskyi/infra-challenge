terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" {
  region = var.region
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
    sid = "AllowAssume"
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
    sid     = "EKSBasicAccess"
    actions = ["eks:DescribeCluster", "eks:AccessKubernetesApi"]
    resources = ["*"]
  }
  statement {
    sid     = "ReadSecurityGroups"
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "ModifyAnySecurityGroup"
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
  policy      = jsonencode({
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

# ECR permissions limited to a single repository
data "aws_iam_policy_document" "ci_ecr" {
  count = var.create_ci_role ? 1 : 0

  statement {
    sid     = "ECRGetAuthToken"
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPushPullSpecificRepo"
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
      "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repo_name}"
    ]
  }
}

resource "aws_iam_policy" "ci_ecr_policy" {
  count       = var.create_ci_role ? 1 : 0
  name        = "eks-ci-ecr-${var.ecr_repo_name}"
  description = "CI push/pull access to a specific ECR repository"
  policy      = data.aws_iam_policy_document.ci_ecr[0].json
}

# Minimal AWS permissions to reach the EKS API (Kubernetes rights via Access Entries)
data "aws_iam_policy_document" "ci_eks" {
  count = var.create_ci_role ? 1 : 0

  statement {
    sid     = "EKSBasicAccess"
    actions = ["eks:DescribeCluster", "eks:AccessKubernetesApi"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_eks_policy" {
  count       = var.create_ci_role ? 1 : 0
  name        = "eks-ci-eks-basic"
  description = "CI minimal AWS permissions to access EKS API; RBAC via Access Entries"
  policy      = data.aws_iam_policy_document.ci_eks[0].json
}

resource "aws_iam_role_policy_attachment" "ci_ecr_attach" {
  count      = var.create_ci_role ? 1 : 0
  role       = aws_iam_role.ci[0].name
  policy_arn = aws_iam_policy.ci_ecr_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "ci_eks_attach" {
  count      = var.create_ci_role ? 1 : 0
  role       = aws_iam_role.ci[0].name
  policy_arn = aws_iam_policy.ci_eks_policy[0].arn
}
