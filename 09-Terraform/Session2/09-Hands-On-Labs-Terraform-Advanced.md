# Session 4: Remote State, Loops & Advanced Patterns — Hands-On Labs

## Overview
In this final session, you'll configure a remote S3 backend with DynamoDB locking, use count and for_each to create multiple resources, implement conditionals, and import existing AWS resources.

---

## Lab 1: Configure S3 Remote Backend with DynamoDB Locking

### Objective
Move your Terraform state from local to S3, with locking via DynamoDB.

### Steps

1. **Create S3 bucket for state (via AWS console or CLI):**
   ```bash
   aws s3 mb s3://my-terraform-state-<your-name>-001 --region <your-region>
   # Note the bucket name (must be globally unique)
   ```

2. **Create DynamoDB table for locking:**
   ```bash
   aws dynamodb create-table \
     --table-name terraform-locks \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
     --region <your-region>
   ```

   or create it via console, the steps are very straightforward:
   - Create a table with the name terraform-lock.
   - Use LockID as the partition key (string type).
   

3. **Create a new project directory:**
   ```bash
   mkdir terraform-remote-state
   cd terraform-remote-state
   ```

4. **Create `backend.tf` (with your bucket name):**
   ```hcl
   terraform {
     backend "s3" {
       bucket         = "my-terraform-state-<your-name>-001"  # Your bucket name
       key            = "dev/terraform.tfstate"
       region         = "<your-region>"
       encrypt        = true
       dynamodb_table = "terraform-locks"
     }
   }
   ```

5. **Create simple `provider.tf` and `main.tf`:**
   ```hcl
   # provider.tf
   terraform {
     required_providers {
       aws = {
         source  = "hashicorp/aws"
         version = "~> 6.0"
       }
     }
   }

   provider "aws" {
     region = "<your-region>"
   }

   # main.tf
   resource "aws_instance" "web" {
     ami           = "<ubuntu_ami_id_from_your_region>>"
     instance_type = "t3.micro"
     tags = { Name = "remote-state-test" }
   }
   ```

6. **Initialize with remote backend:**
   ```bash
   terraform init
   ```
   Terraform prompts: "Do you want to copy state from the local state?"
   Answer: `yes` (if you have existing local state)

7. **Verify state is in S3:**
   ```bash
   aws s3 ls s3://my-terraform-state-<your-name>-001/dev/
   # Should see terraform.tfstate
   ```

8. **Test locking (optional, advanced):**
   In one terminal:
   ```bash
   terraform apply  # Locks state
   ```

   In another terminal:
   ```bash
   terraform plan   # Waits for lock (shows: acquiring lock...)
   ```

   When first apply completes, lock released, second plan proceeds.

### Key Learnings
- Remote state in S3 allows team sharing
- DynamoDB locking prevents concurrent applies
- `terraform.tfstate` no longer in local directory
- State file encrypted at rest and in transit (if encrypted = true)

---

## Lab 2: Use count to Create Multiple EC2 Instances

### Objective
Create N EC2 instances dynamically using count.

### Steps

1. **Update `variables.tf`:**
   ```hcl
   variable "instance_count" {
     type        = number
     description = "Number of EC2 instances to create"
     default     = 1
   }
   ```

2. **Update `main.tf` to use count:**
   ```hcl
   resource "aws_instance" "web" {
     count         = var.instance_count
     ami           = "<ubuntu_ami_id_from_your_region>>"
     instance_type = "t3.micro"

     tags = {
       Name = "web-${count.index}"
       Index = count.index
     }
   }

   output "instance_ids" {
     value       = aws_instance.web[*].id
     description = "All instance IDs"
   }

   output "private_ips" {
     value       = aws_instance.web[*].private_ip
     description = "All private IPs"
   }
   ```

3. **Plan with count = 3:**
   ```bash
   terraform plan -var="instance_count=3"
   ```
   Output: Plan: 3 to add
   - aws_instance.web[0]
   - aws_instance.web[1]
   - aws_instance.web[2]

4. **Apply:**
   ```bash
   terraform apply -var="instance_count=3"
   ```
   Type `yes`. Three EC2 instances created.

5. **View state:**
   ```bash
   terraform state list
   # aws_instance.web[0]
   # aws_instance.web[1]
   # aws_instance.web[2]

   terraform state show aws_instance.web[0]
   ```

6. **Modify count and observe Terraform's behavior:**
   ```bash
   terraform plan -var="instance_count=5"
   ```
   Output: Plan: 2 to add (adds [3] and [4])

   ```bash
   terraform plan -var="instance_count=1"
   ```
   Output: Plan: 2 to destroy (destroys [1] and [2], keeps [0])

   **Note:** Terraform destroys by index order, which can be problematic if instance IDs matter.

### Key Learnings
- `count` creates indexed resources: [0], [1], [2]
- `count.index` = 0, 1, 2
- Splat syntax `[*]` gets all values
- Changing count destroys/creates by index (fragile if adding to middle)

---

## Lab 3: Use for_each to Create Multiple S3 Buckets

### Objective
Use for_each to create named S3 buckets (safer than count for adding/removing items).

### Steps

1. **Update `variables.tf`:**
   ```hcl
   variable "bucket_names" {
     type        = set(string)
     description = "Names of S3 buckets to create"
     default = [
       "logs",
       "data",
       "backups"
     ]
   }
   ```

2. **Create `s3.tf`:**
   ```hcl
   resource "aws_s3_bucket" "main" {
     for_each = var.bucket_names
     bucket   = "my-app-${each.value}-${data.aws_caller_identity.current.account_id}"

     tags = {
       Name = each.value
       Purpose = each.value
     }
   }

   resource "aws_s3_bucket_versioning" "main" {
     for_each = aws_s3_bucket.main
     bucket   = each.value.id

     versioning_configuration {
       status = "Enabled"
     }
   }

   data "aws_caller_identity" "current" {}

   output "bucket_ids" {
     value = {
       for name, bucket in aws_s3_bucket.main : name => bucket.id
     }
     description = "Map of bucket names to IDs"
   }
   ```

3. **Plan to see for_each in action:**
   ```bash
   terraform plan
   ```
   Output:
   - aws_s3_bucket.main["backups"]
   - aws_s3_bucket.main["data"]
   - aws_s3_bucket.main["logs"]

4. **Apply:**
   ```bash
   terraform apply
   ```
   Three S3 buckets created (keyed by name).

5. **Modify buckets by name:**
   Update `variables.tf`:
   ```hcl
   default = [
     "logs",
     "data",
     "backups",
     "archive"  # Add new bucket
   ]
   ```

6. **Plan again:**
   ```bash
   terraform plan
   ```

7. **Remove a bucket:**
   Update `variables.tf`:
   ```hcl
   default = [
     "logs",
     "data"
     # Removed "backups"
   ]
   ```

8. **Plan:**
   ```bash
   terraform plan
   ```

### Key Learnings
- `for_each` keyed by name (safer than index)
- Adding/removing items doesn't shift existing ones
- `each.key` = bucket name, `each.value` = value from set/map
- For_each with maps: `for_each = var.config` and `each.value.attribute`

---

## Lab 4: Implement Conditionals for Prod vs. Dev

### Objective
Use conditionals to create different resources per environment.

### Steps

1. **Update `variables.tf`:**
   ```hcl
   variable "environment" {
     type    = string
     default = "dev"

     validation {
       condition     = contains(["dev", "prod"], var.environment)
       error_message = "Must be dev or prod"
     }
   }
   ```

2. **Update `main.tf` with conditionals:**
   ```hcl
   # Conditional: different instance type per environment
   resource "aws_instance" "web" {
     ami           = "<ubuntu_ami_id_from_your_region>"
     instance_type = var.environment == "prod" ? "t3.large" : "t3.micro"

     tags = {
       Name = "${var.environment}-web"
       Environment = var.environment
     }
   }

   # Conditional: create RDS only in prod
   resource "aws_db_instance" "main" {
     count                = var.environment == "prod" ? 1 : 0
     engine               = "mysql"
     engine_version       = "8.0"
     instance_class       = "db.t3.micro"
     allocated_storage    = 20
     skip_final_snapshot  = var.environment != "prod"

     tags = {
       Name = "${var.environment}-db"
       Environment = var.environment
     }
   }

   output "instance_type" {
     value = aws_instance.web.instance_type
   }

   output "has_database" {
     value = length(aws_db_instance.main) > 0
   }
   ```

3. **Plan for dev:**
   ```bash
   terraform plan -var="environment=dev"
   ```

4. **Plan for prod:**
   ```bash
   terraform plan -var="environment=prod"
   ```

5. **Test the difference:**
   ```bash
   terraform apply -var="environment=dev"
   terraform output instance_type

   terraform destroy -var="environment=dev" --auto-approve
   ```

---

## Lab 5: Import Existing AWS Resource

### Objective
Adopt an existing AWS resource under Terraform management.

### Steps

1. **Create a test resource manually (via AWS console or CLI):**
   ```bash
   aws s3 mb s3://test-import-bucket-$(date +%s)
   # Note the bucket name: test-import-bucket-XXXXX
   ```

2. **Create a resource block in Terraform (without running apply):**
   Edit `s3.tf`:
   ```hcl
   resource "aws_s3_bucket" "imported" {
     # Empty for now - will be populated by import
   }
   ```

3. **Import the bucket into Terraform state:**
   ```bash
   terraform import aws_s3_bucket.imported test-import-bucket-XXXXX
   ```
   Output: Import successful! aws_s3_bucket.imported is now managed.

4. **Check state:**
   ```bash
   terraform state show aws_s3_bucket.imported
   # Shows the bucket attributes from AWS
   ```

5. **Plan to see what's missing:**
   ```bash
   terraform plan
   ```
   May show changes needed (e.g., if bucket has tags in AWS but Terraform config doesn't).

6. **Update resource definition to match AWS state:**
   ```hcl
   resource "aws_s3_bucket" "imported" {
     bucket = "test-import-bucket-XXXXX"
     # Add any other attributes...
   }
   ```

7. **Verify plan is clean:**
   ```bash
   terraform plan
   ```
   Output: No changes (resource matches state).

### Why Import?
- Adopt existing resources without manually recreating
- Prevent accidental destruction of critical resources
- Migrate from manual AWS console to Terraform management

### Key Learnings
- `terraform import <resource_type>.<name> <id>`
- After import, update Terraform code to match actual resource
- Use `terraform state` commands to inspect

---

## Lab 6: Dynamic Blocks for Repetitive Configuration

### Objective
Use dynamic blocks to reduce code repetition.

### Steps

1. **Create `dynamic-blocks.tf`:**
   ```hcl
   variable "ingress_rules" {
     type = list(object({
       from_port = number
       to_port   = number
       protocol  = string
       cidr      = string
     }))
     default = [
       {
         from_port = 80
         to_port   = 80
         protocol  = "tcp"
         cidr      = "0.0.0.0/0"
       },
       {
         from_port = 443
         to_port   = 443
         protocol  = "tcp"
         cidr      = "0.0.0.0/0"
       },
       {
         from_port = 22
         to_port   = 22
         protocol  = "tcp"
         cidr      = "10.0.0.0/8"
       }
     ]
   }

   resource "aws_security_group" "dynamic" {
     name_prefix = "dynamic-sg-"

     dynamic "ingress" {
       for_each = var.ingress_rules
       content {
         from_port   = ingress.value.from_port
         to_port     = ingress.value.to_port
         protocol    = ingress.value.protocol
         cidr_blocks = [ingress.value.cidr]
       }
     }

     egress {
       from_port   = 0
       to_port     = 0
       protocol    = "-1"
       cidr_blocks = ["0.0.0.0/0"]
     }

     tags = { Name = "dynamic-sg" }
   }
   ```

2. **Plan and apply:**
   ```bash
   terraform plan
   terraform apply
   ```
   Output: Security group created with 3 ingress rules dynamically.

3. **Modify rules in tfvars:**
   ```hcl
   # Add or remove rules from ingress_rules list
   # Terraform regenerates the security group
   ```

### Key Learnings
- Dynamic blocks generate nested blocks from lists/maps
- Reduces repetition (especially for security groups, IAM policies)
- Syntax: `dynamic "block_name" { for_each = var.list }`

---