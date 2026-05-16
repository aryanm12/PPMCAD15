region      = "ap-southeast-1"
aws_profile = "prod-profile"
env         = "prod"

# VPC (reserved separate range for prod)
vpc_cidr             = "10.23.0.0/16"
public_subnet_cidrs  = ["10.23.1.0/24", "10.23.2.0/24"]
private_subnet_cidrs = ["10.23.11.0/24", "10.23.12.0/24"]

# Compute (larger instance for prod)
ami_id           = "ami-REPLACE_WITH_PROD_AMI" # <-- replace with hardened prod AMI
instance_type    = "t3.large"
bastion_key_name = "prod-keypair"    # <-- replace with your PROD keypair or use bastion

# Storage
bucket_name = "myorg-learn-tf-prod-001"          # <-- must be globally unique; change as needed

# Optional tags (include cost center / owner)
tags = {
  Owner      = "platform-team"
  Env        = "prod"
  CostCenter = "prod-001"
}