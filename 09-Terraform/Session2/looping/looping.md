# Problem Statement 1:
Deploy Multiple EC2 Instances Using count

## Objective
Create a Terraform configuration to deploy 3 AWS EC2 instances
dynamically using the count meta-argument.

## Requirements:
Use the count parameter to launch 3 instances. Assign
unique names to each instance using the count.index meta-argument.
Output the ID of all created instances.

## Key Considerations
The instance type should be t3.micro. The AMI ID should be passed as a
variable. Use tags to name each instance in the format
example-instance-1, example-instance-2, and example-instance-3.


# Problem Statement 2:
Deploy S3 Buckets for Multiple Environments Using for_each

## Objective
Create a Terraform configuration to deploy S3 buckets for multiple environments dynamically using the for_each meta-argument.

## Requirements
Define a map of environments (e.g., dev, staging, prod)
with unique bucket names should contain your username. Use the for_each meta-argument to create an S3
bucket for each environment. Tag each bucket with the corresponding
environment name.

## Key Considerations
Use the map to link environment names (dev, staging, prod) with their respective bucket names. Ensure
that each bucket has a tag key Environment with the value as the
environment name (e.g., dev, staging, or prod).

## Instructions
Write Terraform configurations for the above problem
statements. Validate your configurations using terraform validate. Apply
the configurations using terraform plan and terraform apply. Verify the
created resources in the AWS console.
