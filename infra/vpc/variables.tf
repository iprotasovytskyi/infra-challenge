variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Project tag"
  type        = string
  default     = "hivemind-infra-challenge"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "hivemind"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "hivemind"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "public_subnets" {
  description = "Public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.20.0.0/20", "10.20.16.0/20", "10.20.32.0/20"]
}

variable "private_subnets" {
  description = "Private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.20.128.0/20", "10.20.144.0/20", "10.20.160.0/20"]
}
