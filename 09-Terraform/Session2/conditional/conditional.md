# Problem Statement 1:
Create an AWS S3 bucket only if a variable enable_bucket is set to true.

## Objective
Define a variable enable_bucket of type bool.
Use a conditional to determine whether to create an S3 bucket.
If enable_bucket is false, no bucket should be created.

# Problem Statement 2:
Dynamically set the EC2 instance type based on the value of a performance variable.

## Objective
Create an EC2 instance.
If performance = "high", use the instance type t3.large.
If performance = "medium", use t3.medium.
For other values, use t3.micro.