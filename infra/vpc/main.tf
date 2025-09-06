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
    key            = "vpc/terraform.tfstate"
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

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  # Availability Zones and subnet CIDRs
  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  enable_dns_hostnames = true
  enable_dns_support   = true

  # NAT gateway configuration
  # Using a single NAT gateway for cost efficiency.
  # For high availability, set one_nat_gateway_per_az = true.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # Tags required for EKS to discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  # General tags
  tags = {
    Project     = var.project
    Environment = var.environment
  }
}
