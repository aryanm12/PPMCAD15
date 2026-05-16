variable "ami_id" {
  description = "AMI id for instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (e.g. t3.micro)"
  type        = string
}

variable "bastion_key_name" {
  description = "SSH key pair name for bastion (must exist in region)"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (module will use index 0 for bastion)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (module will use index 0 for web)"
  type        = list(string)
}

variable "bastion_sg_id" {
  description = "Security group id to attach to bastion"
  type        = string
}

variable "web_sg_id" {
  description = "Security group id to attach to web instance"
  type        = string
}

variable "env" {
  description = "Environment name (dev/qa/staging/prod)"
  type        = string
}

variable "tags" {
  description = "Additional tags to attach to instances"
  type        = map(string)
  default     = {}
}
