# Session 1: Terraform Foundations - Hands-On Labs

## Overview

In this lab session, you'll install Terraform, configure the AWS provider, and deploy your first EC2 instance. By the end, you'll understand the core Terraform workflow (init → plan → apply → destroy) and you'll be comfortable using variables, outputs, data sources, and building a custom VPC with EC2 instances inside it.

**Estimated Time:** 180 minutes (two sittings)
**Prerequisites:** AWS account (with free tier access), terminal/CLI access

---


## Lab 1: Install Terraform & Verify Installation


### Objective
Get Terraform installed on your local machine and verify it's working.

### Steps

1. **Download Terraform** from https://www.terraform.io/downloads.html
   - Choose your OS (macOS, Linux, Windows)
   - Unzip the binary and add it to your PATH

2. **Verify installation:**
   ```bash
   terraform version
   ```
   You should see output like: `Terraform v1.x.x`

3. **Explore Terraform CLI help:**
   ```bash
   terraform -h
   terraform init -h
   terraform plan -h
   terraform apply -h
   terraform destroy -h
   ```
   Get familiar with the main commands you'll be using.

---


## Lab 2: Configure AWS Provider & Create First Terraform Project


### Objective
Set up AWS credentials and create a Terraform project directory with provider configuration.

### Steps

1. **Create a project directory:**
   ```bash
   mkdir terraform-labs
   cd terraform-labs
   ```

2. **Configure AWS credentials.** You have two options:

   **Option A: AWS CLI (recommended)**
   ```bash
   aws configure
   # Enter: Access Key, Secret Key, Region (e.g., us-east-1), output format (json)
   ```
   Terraform will auto-detect credentials from `~/.aws/credentials`

   **Option B: Environment variables**
   ```bash
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   export AWS_DEFAULT_REGION="us-east-1"
   ```

3. **Create `provider.tf` file:**
   ```hcl
   terraform {
     required_providers {
       aws = {
         source  = "hashicorp/aws"
         version = "~> 6.0" # or search for the latest version from https://registry.terraform.io/providers/hashicorp/aws/latest/docs
       }
     }
   }

   provider "aws" {
     region = "xx" # put the region code where you are working
   }
   ```
   This tells Terraform to use AWS provider version 5.x in the us-east-1 region.

4. **Initialize Terraform:**
   ```bash
   terraform init
   ```
   You should see: "Terraform has been successfully configured!"
   - `.terraform/` directory created (provider plugins)
   - `.terraform.lock.hcl` created (locks provider versions)

5. **Verify configuration:**
   ```bash
   terraform validate
   ```
   Output: "Success! The configuration is valid."

### What Happened?
- `terraform init` downloaded the AWS provider plugin
- `.terraform.lock.hcl` locks provider versions for reproducibility
- You're ready to define resources

---


## Lab 3: Create Your First EC2 Instance


### Objective
Write your first resource and deploy it to AWS.

### Steps

1. **Create `main.tf` file:**
   ```hcl
   resource "aws_instance" "web" {
     ami           = "xxx"  # search for latest ubuntu ami id from your region and replace xxx with it
     instance_type = "t4g.micro"               # Free tier eligible

     tags = {
       Name = "MyTerraformWebServer"
     }
   }
   ```
   - `aws_instance` = resource type
   - `web` = logical name (used only by Terraform)
   - `ami` = Amazon Machine Image ID (Ubuntu Linux)
   - `t2.micro` = free tier instance type

2. **Preview changes with terraform plan:**
   ```bash
   terraform plan
   ```

3. **Apply the configuration:**
   ```bash
   terraform apply
   ```
   When prompted, type `yes` to confirm.
   ```

4. **Verify in AWS Console:**
   - Log into AWS Console → EC2 → Instances
   - You should see "MyTerraformWebServer" running
   - Instance ID matches the one in terraform output

### What Happened?
- Terraform converted your HCL into an API call to AWS
- AWS created the EC2 instance
- Terraform stored the resource ID in `terraform.tfstate`

---


## Lab 4: Understanding terraform plan, apply, destroy


### Objective
Practice the full Terraform workflow and understand how plan helps prevent mistakes.

### Steps

1. **Modify the instance (no actual change):**
   - Edit `main.tf` and change the tag:
   ```hcl
   tags = {
     Name = "MyUpdatedWebServer"
     Environment = "dev"
   }
   ```

2. **Plan the change:**
   ```bash
   terraform plan
   ```

   Notice the `~` (changed) and `+` (added) indicators

3. **Apply the change:**
   ```bash
   terraform apply
   ```
   Type `yes`. The instance is updated (no downtime for tag changes).

4. **Try a destructive change (with plan safety):**
   - Edit `main.tf` and change instance_type:
   ```hcl
   instance_type = "t4g.small"  # Changed from t4g.micro
   ```

5. **Plan shows impact:**
   ```bash
   terraform plan
   ```

   Instance must be destroyed and recreated! This is why `plan` is critical.

6. **CANCEL the change (don't apply it):**
   Revert `main.tf` to instance_type = "t4g.micro"

7. **Destroy the instance (cleanup):**
   ```bash
   terraform destroy
   ```
   When prompted, type `yes`.

### Key Learnings
- `terraform plan` ALWAYS before `terraform apply`
- Plan shows exactly what will change
- `-/+` indicator means resource replacement (potentially disruptive)
- Destroy cleans up all managed resources

---


## Lab 5: Explore the State File


### Objective
Understand what Terraform stores in the state file and why it's important.

### Steps

1. **List files in your project:**
   ```bash
   ls -la
   ```
   You should see:
   - `provider.tf` - provider configuration
   - `main.tf` - your resources
   - `.terraform/` - cached provider plugins
   - `.terraform.lock.hcl` - provider version lock
   - `terraform.tfstate` - your infrastructure state (only if resources exist)

2. **If you destroyed the instance, recreate it:**
   ```bash
   terraform apply
   ```
   Say `yes`.

3. **Examine the state file (read-only):**
   ```bash
   cat terraform.tfstate
   ```
   You'll see:
   - JSON file mapping resources to cloud IDs
   - Instance ID: `"id": "i-1234567890abcdef0"`
   - AMI: `"ami": "ami-0c55b159cbfafe1f0"`
   - Tags, VPC ID, network interfaces, etc.

4. **State file is sensitive!**
   - Contains resource attributes (IPs, DNS names, passwords)
   - Example: RDS database password is stored in plaintext
   - **NEVER commit to Git** - add to `.gitignore`

5. **Create `.gitignore`:**
   ```bash
   cat > .gitignore << EOF
   terraform.tfstate
   terraform.tfstate.*
   .terraform/
   .terraform.lock.hcl
   *.tfvars
   !example.tfvars
   EOF
   ```

6. **Verify with terraform state commands:**
   ```bash
   terraform state list
   # Output: aws_instance.web

   terraform state show aws_instance.web
   # Output: full resource details
   ```

### Key Learnings
- State file is the source of truth for Terraform
- Maps logical names (aws_instance.web) to cloud IDs
- Sensitive data lives here - treat it securely
- Always add terraform.tfstate to .gitignore

---


## Lab 6: Use terraform fmt & validate


### Objective
Learn Terraform's built-in tools for code quality and consistency.

### Steps

1. **Make your HCL messy (intentionally):**
   Edit `main.tf`:
   ```hcl
   resource "aws_instance" "web" {
   ami="xxx"  # search for latest ubuntu ami id from your region and replace xxx with it
     instance_type    =    "t4g.micro"

   tags={
   Name="MyWebServer"
   }
   }
   ```

2. **Format with terraform fmt:**
   ```bash
   terraform fmt
   ```
   
3. **Validate syntax:**
   ```bash
   terraform validate
   ```

4. **Introduce a syntax error (test validation):**
   Edit `main.tf` and break it:
   ```hcl
   resource "aws_instance" "web" {
     ami = "xxx"
     instance_type = "t4g.micro"
     # Missing closing brace
   ```

5. **Run validate again:**
   ```bash
   terraform validate
   ```
   Error output pinpoints the problem!

6. **Fix it and validate passes again.**

### Key Learnings
- `terraform fmt` auto-formats HCL (like `go fmt` for Go)
- `terraform validate` catches syntax errors early
- Run both before committing to Git

---


## Lab 7: Create variables.tf with Different Types


### Objective
Understand variable types and create a reusable variables file.

### Steps

1. **Create a new project directory:**
   ```bash
   mkdir terraform-vpc-labs
   cd terraform-vpc-labs
   ```

2. **Create `variables.tf` with primitives:**
   ```hcl
   variable "aws_region" {
     type        = string
     description = "AWS region to deploy to"
     default     = "us-east-1"
   }

   variable "environment" {
     type        = string
     description = "Environment name"
     default     = "dev"

     validation {
       condition     = contains(["dev", "qa", "prod"], var.environment)
       error_message = "Environment must be dev, qa, or prod."
     }
   }

   variable "instance_count" {
     type        = number
     description = "Number of EC2 instances to create"
     default     = 1
   }

   variable "instance_type" {
     type        = string
     description = "Instance type for EC2 instance"
     default     = "t3.micro"
   }

   variable "enable_nat_gateway" {
     type        = bool
     description = "Create NAT Gateway for private subnets?"
     default     = false
   }

   variable "enable_dns_hostnames" {
     type        = bool
     description = "Enable DNS hostnames in the VPC"
     default     = true
   }

   variable "enable_dns_support" {
     type        = bool
     description = "Enable DNS support in the VPC"
     default     = true
   }

   variable "vpc_cidr" {
     type        = string
     description = "CIDR block for the VPC"
     default     = "10.0.0.0/16"
   }

   variable "ami_owners" {
     type        = list(string)
     description = "List of AMI owner IDs to filter on"
     default     = ["amazon"]
   }

   variable "ami_name_pattern" {
     type        = string
     description = "Name filter pattern for the AMI lookup"
     default     = "al2023-ami-*-x86_64"
   }


   ```

3. **Add complex types (lists and maps):**
   ```hcl
   variable "availability_zones" {
     type        = list(string)
     description = "List of AZs to use"
     default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
   }

   variable "common_tags" {
     type = map(string)
     description = "Common tags for all resources"
     default = {
       Terraform   = "true"
       Project     = "VPC-Labs"
       Owner       = "DevOps-Team"
     }
   }

   variable "subnet_config" {
     type = list(object({
       name              = string
       cidr              = string
       availability_zone = string
       type              = string  # "public" or "private"
     }))
     description = "Subnet configuration"
     default = [
       {
         name              = "public-1a"
         cidr              = "10.0.1.0/24"
         availability_zone = "us-east-1a"
         type              = "public"
       },
       {
         name              = "private-1b"
         cidr              = "10.0.2.0/24"
         availability_zone = "us-east-1b"
         type              = "private"
       }
     ]
   }
   ```

4. **Test variable validation:**
   Create `provider.tf`:
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

5. **Create main.tf:**
   Create `main.tf`:
   ```hcl
      # ----------------------------
      # VPC
      # ----------------------------
      resource "aws_vpc" "main" {
      cidr_block           = var.vpc_cidr
      enable_dns_hostnames = var.enable_dns_hostnames
      enable_dns_support   = var.enable_dns_support

      tags = {
         Name        = "${var.environment}-vpc"
         Environment = var.environment
      }
      }

      # ----------------------------
      # Internet Gateway
      # ----------------------------
      resource "aws_internet_gateway" "main" {
      vpc_id = aws_vpc.main.id

      tags = {
         Name        = "${var.environment}-igw"
         Environment = var.environment
      }
      }

      # ----------------------------
      # Subnets (driven by subnet_config)
      # ----------------------------
      resource "aws_subnet" "this" {
      for_each = { for s in var.subnet_config : s.name => s }

      vpc_id                  = aws_vpc.main.id
      cidr_block              = each.value.cidr
      availability_zone       = each.value.availability_zone
      map_public_ip_on_launch = each.value.type == "public"

      tags = {
         Name        = "${var.environment}-${each.value.name}"
         Type        = each.value.type
         Environment = var.environment
      }
      }

      # ----------------------------
      # NAT Gateway (conditional via bool var)
      # ----------------------------
      resource "aws_eip" "nat" {
      count  = var.enable_nat_gateway ? 1 : 0
      domain = "vpc"

      tags = {
         Name        = "${var.environment}-nat-eip"
         Environment = var.environment
      }
      }

      resource "aws_nat_gateway" "main" {
      count = var.enable_nat_gateway ? 1 : 0

      allocation_id = aws_eip.nat[0].id
      subnet_id = [
         for s in var.subnet_config : aws_subnet.this[s.name].id
         if s.type == "public"
      ][0]

      tags = {
         Name        = "${var.environment}-nat"
         Environment = var.environment
      }

      depends_on = [aws_internet_gateway.main]
      }

      # ----------------------------
      # AMI lookup (driven by variables)
      # ----------------------------
      data "aws_ami" "app" {
      most_recent = true
      owners      = var.ami_owners

      filter {
         name   = "name"
         values = [var.ami_name_pattern]
      }
      }

      # ----------------------------
      # EC2 instances (count driven by instance_count)
      # ----------------------------
      resource "aws_instance" "app" {
      count = var.instance_count

      ami           = data.aws_ami.app.id
      instance_type = var.instance_type

      subnet_id = [
         for s in var.subnet_config : aws_subnet.this[s.name].id
         if s.type == "public"
      ][0]

      tags = {
         Name        = "${var.environment}-app-${count.index + 1}"
         Environment = var.environment
      }
      }
   ```
6. **Validate the configuration:**
   ```bash
   terraform fmt
   terraform init
   terraform validate
   ```
   Output: "Success! The configuration is valid."

7. **Create a terraform.tfvars file (for defaults):**
   ```bash
   cat > terraform.tfvars << EOF
      aws_region         = "ap-south-1" # update as per your region
      environment        = "dev"
      instance_count     = 1
      instance_type      = "t3.micro"
      enable_nat_gateway = false
      vpc_cidr           = "10.0.0.0/16"
      availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
      subnet_config = [
         {
            name              = "public-1a"
            cidr              = "10.0.1.0/24"
            availability_zone = "ap-south-1a"
            type              = "public"
         },
         {
            name              = "private-1b"
            cidr              = "10.0.2.0/24"
            availability_zone = "ap-south-1b"
            type              = "private"
         }
      ]
   EOF
   ```

   Test with: `terraform plan` (uses .tfvars values)

### Key Learnings
- Variable types: string, number, bool, list, map, object
- Validation rules prevent invalid inputs
- Variables can have defaults; if no default, they're required
- Multiple input methods: .tfvars, CLI, env vars

---


## Lab 8: Use Data Sources to Find an AMI


### Objective
Query AWS to find the latest Ubuntu AMI instead of hardcoding.

### Steps

1. **Create `data-sources.tf`:**
   ```hcl
   data "aws_ami" "ubuntu" {
     most_recent = true

     filter {
       name   = "name"
       values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
     }

     filter {
       name   = "virtualization-type"
       values = ["hvm"]
     }

     owners = ["099720109477"] # Canonical
   }

   # Output the AMI ID (for inspection)
   output "ubuntu_ami_id" {
     value       = data.aws_ami.ubuntu.id
     description = "Latest Ubuntu 22.04 AMI ID"
   }
   ```

2. **Plan to see the data source in action:**
   ```bash
   terraform plan
   ```
   Output shows: data.aws_ami.ubuntu will be read.

3. **Apply to fetch the AMI:**
   ```bash
   terraform apply
   ```
   The output shows the latest Ubuntu AMI ID.

### Why Data Sources?
- Always get the latest AMI (no manual updates)
- Reference existing resources without managing them
- Used in next lab to pass AMI ID to EC2

---

## Lab 9: Use locals to DRY up your configuration

### Objective
Use a `locals` block to compute values once and reference them everywhere - cleaner than repeating string interpolations.

### Steps

1. **In your project, declare variables for environment context:**
   ```hcl
   variable "account" {
     type    = string
     default = "learning"
   }

   variable "environment" {
     type    = string
     default = "dev"
   }
   ```

2. **Add a `locals` block to compose a common prefix and shared tags:**
   ```hcl
   locals {
     common_prefix = "${var.account}-${var.environment}"

     common_tags = {
       Project   = "learning"
       ManagedBy = "Terraform"
       Owner     = var.account
     }
   }
   ```

3. **Reference the locals from one or more resources:**
   ```hcl
   resource "aws_subnet" "public" {
     vpc_id     = data.aws_vpc.example.id
     cidr_block = "172.31.128.0/28"

     tags = merge(local.common_tags, {
       Name = "${local.common_prefix}-pub-subnet"
     })
   }

   resource "aws_subnet" "private" {
     vpc_id     = data.aws_vpc.example.id
     cidr_block = "172.31.196.0/28"

     tags = merge(local.common_tags, {
       Name = "${local.common_prefix}-priv-subnet"
     })
   }
   ```

4. **Run plan and apply:**
   ```bash
   terraform plan
   terraform apply
   ```
   Both subnets will be tagged with the shared `common_tags` plus a unique `Name` built from `local.common_prefix`.

5. **Tweak one place, see it propagate:**
   Change `default` of `environment` to `qa` and run `terraform plan` again. Every tag derived from `local.common_prefix` updates.

### When to reach for locals vs. variables
- **Variables** are inputs from outside the module (CLI, tfvars, env vars).
- **Locals** are computed inside the module - composed strings, conditional expressions, merged maps. They don't accept input.
- Use locals when the same expression repeats, or when an expression is complex enough to deserve a name.

---
