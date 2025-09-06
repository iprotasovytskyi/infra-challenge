terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  profile = "hivemind"
}

# S3 bucket для Terraform state
resource "aws_s3_bucket" "tf_state" {
  bucket        = var.state_bucket
  force_destroy = true
  tags = { Purpose = "terraform-state"}
}

# Block public access
resource "aws_s3_bucket_public_access_block" "pab" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning
resource "aws_s3_bucket_versioning" "ver" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

# Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB lock table
resource "aws_dynamodb_table" "tf_lock" {
  name         = var.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Purpose = "terraform-lock"}
}

output "state_bucket" { value = aws_s3_bucket.tf_state.bucket }
output "lock_table"   { value = aws_dynamodb_table.tf_lock.name }
