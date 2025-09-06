terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
  backend "s3" {
    bucket         = "hivemind-tf-state" # <- your S3 bucket name from bootstrap
    key            = "iam/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tf-lock-hivemind-dev" # <- your DynamoDB table name from bootstrap
    encrypt        = true
    profile        = "hivemind"
  }
}

provider "aws" {
  region  = "eu-central-1"
  profile = "hivemind"
}

module "iam" {
  source = "../modules/iam"

  # Human admin role (you can point trusted principals to your SSO/IAM identities)
  create_human_admin_role = true
  human_admin_role_name   = "eks-human-admin"
  human_admin_trusted_principals = [
    "arn:aws:iam::959413831332:user/ihor"
    # or "arn:aws:iam::<ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/<Your-SSO-Role>"
  ]

  # CI role via GitHub OIDC
  create_github_oidc_provider = true # set to false if already created account-wide
  create_ci_role              = true
  ci_role_name                = "eks-ci-role"
  github_repo                 = "iprotasovytskyi/infra-challenge"
  github_branch               = "main"

  # Narrow ECR permissions to a single repo name
  ecr_repo_name = "greeter"
}

output "human_admin_role_arn" {
  value = module.iam.human_admin_role_arn
}

output "ci_role_arn" {
  value = module.iam.ci_role_arn
}
