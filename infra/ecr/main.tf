terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket         = "hivemind-tf-state" # <- your S3 bucket name from bootstrap
    key            = "ecr/terraform.tfstate"
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

# Who am I (handy for ARNs/outputs if needed)
data "aws_caller_identity" "current" {}

# --- ECR repository (simple & safe) ---
resource "aws_ecr_repository" "this" {
  name                 = var.repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = var.force_delete

  tags = {
    Name        = var.repo_name
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}

# Optional: basic lifecycle for untagged images to keep registry tidy
resource "aws_ecr_lifecycle_policy" "this" {
  count      = var.enable_lifecycle ? 1 : 0
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_retention_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_retention_days
        }
        action = { type = "expire" }
      }
    ]
  })
}

# --- OPTIONAL: allow EKS nodes to pull from ECR ---
# If you pass a node role name, we attach AmazonEC2ContainerRegistryReadOnly.
data "aws_iam_policy" "ecr_readonly" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  count      = var.attach_readonly_to_node_role && length(var.node_role_name) > 0 ? 1 : 0
  role       = var.node_role_name
  policy_arn = data.aws_iam_policy.ecr_readonly.arn
}