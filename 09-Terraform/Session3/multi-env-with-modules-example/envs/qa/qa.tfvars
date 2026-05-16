region      = "ap-southeast-1"
aws_profile = "qa-profile"
env         = "qa"

# VPC
vpc_cidr             = "10.21.0.0/16"
public_subnet_cidrs  = ["10.21.1.0/24", "10.21.2.0/24"]
private_subnet_cidrs = ["10.21.11.0/24", "10.21.12.0/24"]

# Compute
ami_id           = "ami-REPLACE_WITH_QA_AMI" # <-- replace with valid AMI for region
instance_type    = "t3.small"
bastion_key_name = "qa-keypair"      # <-- replace with your QA keypair name

# Storage
bucket_name = "myorg-learn-tf-qa-001" # <-- must be globally unique; change as needed

# Optional tags
tags = {
  Owner      = "platform-team"
  Env        = "qa"
  CostCenter = "qa-001"
}
