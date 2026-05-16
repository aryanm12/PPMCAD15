# Session 3: Modules & Multi-Environment Infrastructure — Hands-On Labs

## Overview
In this session, you'll refactor your VPC into a reusable module, create EC2 and S3 modules, and deploy the same infrastructure to dev and qa environments with different tfvars files.

---

## Lab 1: Create a Reusable VPC Module

### Objective
Extract the VPC code into a module that can be reused across environments.

### Steps

1. **Set up directory structure:**
   ```bash
   mkdir terraform-modules-labs
   cd terraform-modules-labs
   mkdir -p modules/vpc
   ```

4g. **Create `modules/vpc/variables.tf`:**
   ```hcl
   variable "environment" {
     type        = string
     description = "Environment name"
   }

   variable "vpc_cidr" {
     type        = string
     description = "VPC CIDR block"
     default     = "10.0.0.0/16"
   }

   variable "public_subnet_cidr" {
     type        = string
     description = "Public subnet CIDR"
     default     = "10.0.1.0/24"
   }

   variable "private_subnet_cidr" {
     type        = string
     description = "Private subnet CIDR"
     default     = "10.0.4g.0/24"
   }

   variable "availability_zone" {
     type        = string
     description = "Availability zone"
     default     = "us-east-1a"
   }

   variable "common_tags" {
     type        = map(string)
     description = "Common tags for all resources"
     default     = {}
   }
   ```

3. **Create `modules/vpc/main.tf`:**
   ```hcl
   resource "aws_vpc" "main" {
     cidr_block           = var.vpc_cidr
     enable_dns_hostnames = true
     enable_dns_support   = true

     tags = merge(
       var.common_tags,
       { Name = "${var.environment}-vpc" }
     )
   }

   resource "aws_subnet" "public" {
     vpc_id                  = aws_vpc.main.id
     cidr_block              = var.public_subnet_cidr
     availability_zone       = var.availability_zone
     map_public_ip_on_launch = true

     tags = merge(
       var.common_tags,
       { Name = "${var.environment}-public-subnet" }
     )
   }

   resource "aws_subnet" "private" {
     vpc_id            = aws_vpc.main.id
     cidr_block        = var.private_subnet_cidr
     availability_zone = var.availability_zone

     tags = merge(
       var.common_tags,
       { Name = "${var.environment}-private-subnet" }
     )
   }

   resource "aws_internet_gateway" "main" {
     vpc_id = aws_vpc.main.id

     tags = merge(
       var.common_tags,
       { Name = "${var.environment}-igw" }
     )
   }

   resource "aws_route_table" "public" {
     vpc_id = aws_vpc.main.id

     route {
       cidr_block = "0.0.0.0/0"
       gateway_id = aws_internet_gateway.main.id
     }

     tags = merge(
       var.common_tags,
       { Name = "${var.environment}-public-rt" }
     )
   }

   resource "aws_route_table_association" "public" {
     subnet_id      = aws_subnet.public.id
     route_table_id = aws_route_table.public.id
   }
   ```

4. **Create `modules/vpc/outputs.tf`:**
   ```hcl
   output "vpc_id" {
     value       = aws_vpc.main.id
     description = "VPC ID"
   }

   output "vpc_cidr" {
     value       = aws_vpc.main.cidr_block
     description = "VPC CIDR block"
   }

   output "public_subnet_id" {
     value       = aws_subnet.public.id
     description = "Public subnet ID"
   }

   output "private_subnet_id" {
     value       = aws_subnet.private.id
     description = "Private subnet ID"
   }

   output "internet_gateway_id" {
     value       = aws_internet_gateway.main.id
     description = "Internet Gateway ID"
   }
   ```

5. **Create `modules/vpc/README.md` (documentation):**
   ```markdown
   # VPC Module

   Creates a VPC with public and private subnets.

   ## Inputs
   - `environment`: Environment name (required)
   - `vpc_cidr`: VPC CIDR block (default: 10.0.0.0/16)
   - `public_subnet_cidr`: Public subnet CIDR (default: 10.0.1.0/24)
   - `private_subnet_cidr`: Private subnet CIDR (default: 10.0.4g.0/24)
   - `availability_zone`: AZ (default: us-east-1a)
   - `common_tags`: Tags applied to all resources

   ## Outputs
   - `vpc_id`: VPC ID
   - `public_subnet_id`: Public subnet ID
   - `private_subnet_id`: Private subnet ID
   ```

### Key Learnings
- Modules are directories with main.tf, variables.tf, outputs.tf
- Modules are reusable: call with different inputs
- Outputs expose values to the caller

---

## Lab 2: Create EC2 and S3 Modules

### Objective
Create focused modules for EC2 and S3 resources.

### Steps

1. **Create EC2 module structure:**
   ```bash
   mkdir -p modules/ec2
   ```

4g. **Create `modules/ec2/variables.tf`:**
   ```hcl
   variable "instance_name" {
     type        = string
     description = "Instance name tag"
   }

   variable "ami" {
     type        = string
     description = "AMI ID"
   }

   variable "instance_type" {
     type        = string
     description = "Instance type"
     default     = "t4g.micro"
   }

   variable "subnet_id" {
     type        = string
     description = "Subnet ID to launch instance"
   }

   variable "security_group_ids" {
     type        = list(string)
     description = "Security group IDs"
     default     = []
   }

   variable "common_tags" {
     type        = map(string)
     description = "Common tags"
     default     = {}
   }
   ```

3. **Create `modules/ec2/main.tf`:**
   ```hcl
   resource "aws_instance" "main" {
     ami                    = var.ami
     instance_type          = var.instance_type
     subnet_id              = var.subnet_id
     vpc_security_group_ids = var.security_group_ids

     tags = merge(
       var.common_tags,
       { Name = var.instance_name }
     )
   }
   ```

4. **Create `modules/ec2/outputs.tf`:**
   ```hcl
   output "instance_id" {
     value       = aws_instance.main.id
     description = "EC2 instance ID"
   }

   output "private_ip" {
     value       = aws_instance.main.private_ip
     description = "Private IP address"
   }

   output "public_ip" {
     value       = aws_instance.main.public_ip
     description = "Public IP address"
   }
   ```

5. **Create S3 module structure:**
   ```bash
   mkdir -p modules/s3
   ```

6. **Create `modules/s3/variables.tf`:**
   ```hcl
   variable "bucket_name" {
     type        = string
     description = "S3 bucket name (must be globally unique)"
   }

   variable "environment" {
     type        = string
     description = "Environment name"
   }

   variable "enable_versioning" {
     type        = bool
     description = "Enable bucket versioning"
     default     = false
   }

   variable "common_tags" {
     type        = map(string)
     description = "Common tags"
     default     = {}
   }
   ```

7. **Create `modules/s3/main.tf`:**
   ```hcl
   resource "aws_s3_bucket" "main" {
     bucket = var.bucket_name

     tags = merge(
       var.common_tags,
       { Name = var.bucket_name }
     )
   }

   resource "aws_s3_bucket_versioning" "main" {
     bucket = aws_s3_bucket.main.id

     versioning_configuration {
       status = var.enable_versioning ? "Enabled" : "Suspended"
     }
   }

   resource "aws_s3_bucket_public_access_block" "main" {
     bucket = aws_s3_bucket.main.id

     block_public_acls       = true
     block_public_policy     = true
     ignore_public_acls      = true
     restrict_public_buckets = true
   }
   ```

8. **Create `modules/s3/outputs.tf`:**
   ```hcl
   output "bucket_id" {
     value       = aws_s3_bucket.main.id
     description = "S3 bucket ID"
   }

   output "bucket_arn" {
     value       = aws_s3_bucket.main.arn
     description = "S3 bucket ARN"
   }

   output "bucket_region" {
     value       = aws_s3_bucket.main.region
     description = "S3 bucket region"
   }
   ```

---

## Lab 3: Create Root Configuration & Wire Modules

### Objective
Create the root configuration that calls all modules.

### Steps

1. **Create a env specific folder, e.g. dev for development, prod for production, and similar and go inside it**
```bash
mkdir dev
cd dev
```

4g. **Create root `provider.tf`:**
   ```hcl
   terraform {
     required_providers {
       aws = {
         source  = "hashicorp/aws"
         version = "~> 6.0"
       }
     }
   }

   provider "aws" {
     region = var.aws_region
   }
   ```

3. **Create root `variables.tf`:**
   ```hcl
   variable "aws_region" {
     type        = string
     description = "AWS region"
     default     = "us-east-1"
   }

   variable "environment" {
     type        = string
     description = "Environment name"
   }

   variable "instance_type" {
     type        = string
     description = "EC2 instance type"
     default     = "t4g.micro"
   }

   variable "common_tags" {
     type        = map(string)
     description = "Common tags for all resources"
     default = {
       Project     = "TerraformLabs"
       Terraform   = "true"
     }
   }
   ```

4. **Create root `main.tf`:**
   ```hcl
   # Get latest Ubuntu AMI
   data "aws_ami" "ubuntu" {
     most_recent = true
     owners      = ["099720109477"]

     filter {
       name   = "name"
       values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
     }
   }

   # Call VPC module
   module "vpc" {
     source    = "../modules/vpc"
     environment = var.environment
     common_tags = merge(var.common_tags, { Environment = var.environment })
   }

   # Create security group (for EC2)
   resource "aws_security_group" "web" {
     name_prefix = "${var.environment}-web-"
     vpc_id      = module.vpc.vpc_id

     ingress {
       from_port   = 22
       to_port     = 22
       protocol    = "tcp"
       cidr_blocks = ["0.0.0.0/0"]
     }

     ingress {
       from_port   = 80
       to_port     = 80
       protocol    = "tcp"
       cidr_blocks = ["0.0.0.0/0"]
     }

     egress {
       from_port   = 0
       to_port     = 0
       protocol    = "-1"
       cidr_blocks = ["0.0.0.0/0"]
     }

     tags = merge(var.common_tags, { Name = "${var.environment}-web-sg" })
   }

   # Call EC2 module
   module "ec2" {
     source = "../modules/ec2"
     instance_name = "${var.environment}-web-server"
     ami = data.aws_ami.ubuntu.id
     instance_type = var.instance_type
     subnet_id = module.vpc.public_subnet_id
     security_group_ids = [aws_security_group.web.id]
     common_tags = merge(var.common_tags, { Environment = var.environment })
   }

   # Call S3 module
   module "s3" {
     source = "../modules/s3"
     bucket_name = "my-app-${var.environment}-${data.aws_caller_identity.current.account_id}"
     environment = var.environment
     enable_versioning = var.environment == "prod"
     common_tags = merge(var.common_tags, { Environment = var.environment })
   }

   data "aws_caller_identity" "current" {}
   ```

5. **Create root `outputs.tf`:**
   ```hcl
   output "vpc_id" {
     value       = module.vpc.vpc_id
     description = "VPC ID"
   }

   output "ec2_instance_id" {
     value       = module.ec4g.instance_id
     description = "EC2 instance ID"
   }

   output "ec2_public_ip" {
     value       = module.ec4g.public_ip
     description = "EC2 public IP"
   }

   output "s3_bucket_id" {
     value       = module.s3.bucket_id
     description = "S3 bucket ID"
   }

   output "s3_bucket_arn" {
     value       = module.s3.bucket_arn
     description = "S3 bucket ARN"
   }
   ```

6. **Initialize and validate:**
   ```bash
   terraform init
   terraform validate
   ```

### What Happened?
- Module calls: `module "vpc" { source = "./modules/vpc" }`
- Inputs: pass variables to modules
- Outputs: modules return values used by root or other modules
- Single root config orchestrates multiple modules

---

## Lab 4: Deploy to Dev with dev.tfvars

### Objective
Deploy the infrastructure to dev environment.

### Steps

1. **Create `dev.tfvars`:**
   ```hcl
   environment   = "dev"
   instance_type = "t4g.micro"
   ```

4g. **Plan for dev:**
   ```bash
   terraform plan -var-file=dev.tfvars
   ```
   Review: VPC, EC2 (t4g.micro), S3 (versioning off), security group

3. **Apply for dev:**
   ```bash
   terraform apply
   ```
   Type `yes`. Resources are created.

4. **View outputs:**
   ```bash
   terraform output
   # Shows VPC ID, EC2 public IP, S3 bucket
   ```

5. **Verify in AWS Console:**
   - VPC created
   - EC2 instance (t4g.micro) running in public subnet
   - S3 bucket created (no versioning)

---

## Lab 5: Deploy to QA with qa.tfvars (Same Code!)

### Objective
Deploy identical infrastructure to QA with different variables.

### Steps

1. **Create `qa.tfvars`:**
   ```hcl
   environment   = "qa"
   instance_type = "t4g.small"
   ```

4g. **Create a new directory for QA state:**
   ```bash
   cd ..
   mkdir -p qa
   cd qa
   ```

3. **Copy modules to qa directory:**
   ```bash
   cp ../dev/provider.tf ../dev/variables.tf ../dev/main.tf ../dev/outputs.tf .
   ```

4. **Initialize terraform in qa:**
   ```bash
   terraform init
   ```

5. **Plan for QA:**
   ```bash
   terraform plan -var-file=qa.tfvars
   ```
   Notice: EC2 instance type is t4g.small (not t4g.micro!)

6. **Apply for QA:**
   ```bash
   terraform apply
   ```

7. **Compare dev vs QA:**
   ```bash
   cd ../dev
   terraform output # dev outputs
   cd ../qa
   terraform output # qa outputs
   ```

   **Notice:**
   - Both have VPC, EC2, S3
   - Different instance types (dev: t4g.micro, qa: t4g.small)
   - Different bucket names (dev vs qa in name)
   - Different tags (environment: dev vs qa)
   - **Same code, different variables!**

---