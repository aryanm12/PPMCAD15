region      = "ap-southeast-1"
aws_profile = "staging-profile"
env         = "staging"

# VPC
vpc_cidr             = "10.22.0.0/16"
public_subnet_cidrs  = ["10.22.1.0/24", "10.22.2.0/24"]
private_subnet_cidrs = ["10.22.11.0/24", "10.22.12.0/24"]

# Compute
ami_id           = "ami-REPLACE_WITH_STAGING_AMI"  # <-- replace with valid AMI for region
instance_type    = "t3.medium"
bastion_key_name = "staging-keypair"     # <-- replace with your staging keypair name

# Storage
bucket_name = "myorg-learn-tf-staging-001"  # <-- must be globally unique; change as needed

# Optional tags
tags = {
  Owner      = "platform-team"
  Env        = "staging"
  CostCenter = "staging-001"
}