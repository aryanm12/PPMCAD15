Terraform Multi-Environment Infrastructure
-------------------------------------------

This repository provisions a complete AWS environment (VPC, EC2 bastion + web server, S3 storage, IAM roles/policies) using Terraform modules and isolated environment folders.

The design follows AWS & Terraform best practices:
- One reusable set of modules
- Multiple environment folders (dev, qa, staging, prod)
- Each environment has its own backend, its own provider, its own state file
- Remote state stored in S3 with DynamoDB state locking
- Zero duplication of logic - only *.tfvars change per environment

📁 Repository Structure
learn-tf-modules/
    modules/
        vpc/      # VPC, subnets, IGW, NAT, route tables, SGs
        ec2/      # Bastion + Web EC2 instances
        s3/       # S3 bucket + IAM access policy
    envs/
        dev/
            provider.tf
            main.tf
            variables.tf
            dev.tfvars
        qa/
            provider.tf
            main.tf
            variables.tf
            qa.tfvars
        staging/
            provider.tf
            main.tf
            variables.tf
            staging.tfvars
        prod/
            provider.tf
            main.tf
            variables.tf
            prod.tfvars
README.md

🏗️ What This Infrastructure Creates

Each environment provisions:

🔹 Networking (VPC Module)

1 VPC
2 Public Subnets
2 Private Subnets
Internet Gateway
NAT Gateway
Public & Private Route Tables
Bastion SG + Web Security Group

🔹 Compute (EC2 Module)
Bastion host (public subnet)
Web server (private subnet)
IAM Instance Profile attached to web server

🔹 Storage (S3 Module)
Private S3 bucket
Public access block
Optional versioning
IAM policy for EC2 to access bucket

State is fully isolated per environment via S3 backend keys and DynamoDB locking.

🔧 Prerequisites
You must pre-create the Terraform backend:
1️⃣ S3 bucket for state
Create once: <unique-name>, e.g.: myorg-learn-tf-prod-001

2️⃣ DynamoDB table for state locking
 Name "terraform-locks" (you can keep the same name or any other name as well) with Partition key LockID (string)

3️⃣ AWS CLI configured

Run:
aws configure
Or use profiles:
dev-profile
qa-profile
staging-profile
prod-profile

▶️ How to Deploy an Environment

Each environment folder is a standalone Terraform project.

Example: Deploying dev

cd envs/dev
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars

Deploy qa:

cd envs/qa
terraform init
terraform plan -var-file=qa.tfvars
terraform apply -var-file=qa.tfvars

Deploy staging:

cd envs/staging
terraform init
terraform plan -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars

Deploy prod:

cd envs/prod
terraform init
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars


Each folder uses its own backend key:

learn-tf-modules/dev/terraform.tfstate
learn-tf-modules/qa/terraform.tfstate
learn-tf-modules/staging/terraform.tfstate
learn-tf-modules/prod/terraform.tfstate

This ensures total state isolation.

🔒 State Locking

Terraform uses:
S3 bucket -> to store state
DynamoDB table -> to lock state during changes

This prevents accidental:
double applies
concurrent modifications
state corruption
No two environments share the same state file.

⚠️ Production Notes

Before applying to prod:
- Restrict SSH CIDRs in prod (0.0.0.0/0 → replace with office WAN IP ranges or restricted IP ranges).
- Use hardened AMIs or golden images.
- Consider larger instances and multiple web servers (ASG).
- Use proper IAM roles (least privilege).

🧹 Cleanup

To destroy an environment:
terraform destroy -var-file=dev.tfvars

(Use caution - never destroy prod without review.)