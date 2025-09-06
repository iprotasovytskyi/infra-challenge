variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket" {
  description = "Globally-unique S3 bucket name for TF state (e.g., hivemind-tf-state-ihor-dev)"
  type        = string
  default = "hivemind-tf-state"
}

variable "lock_table" {
  description = "DynamoDB table name for TF state lock"
  type        = string
  default     = "tf-lock-hivemind-dev"
}
