variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDRs for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDRs for private subnets"
  type        = list(string)
}

variable "env" {
  description = "Environment name (dev/qa/staging/prod)"
  type        = string
}

variable "tags" {
  description = "Additional tags to attach to resources"
  type        = map(string)
  default     = {}
}
