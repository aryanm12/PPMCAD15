output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "bastion_ip" {
  value = module.ec2.bastion_public_ip
}

output "web_private_ip" {
  value = module.ec2.web_private_ip
}

output "s3_bucket" {
  value = module.s3.bucket_id
}