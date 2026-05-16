# Provider / env
variable "region" {
  type        = string
  description = "AWS region for this environment"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile (or leave blank to use default credentials)"
  default     = ""
}

variable "env" {
  type        = string
  description = "Environment name (dev/qa/staging/prod)"
}

# VPC inputs
variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of public subnet CIDRs"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of private subnet CIDRs"
}

# Compute inputs
variable "ami_id" {
  type        = string
  description = "AMI ID to use for EC2 (region-specific)"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
}

variable "bastion_key_name" {
  type        = string
  description = "Existing EC2 key pair name for bastion"
}

# Storage inputs
variable "bucket_name" {
  type        = string
  description = "Globally-unique S3 bucket name for app data"
}

# Optional tags
variable "tags" {
  description = "Map of additional tags applied to resources"
  type        = map(string)
  default     = {}
}
