output "vpc_id" {
  description = "VPC id"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "List of public subnet ids"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "List of private subnet ids"
  value       = [for s in aws_subnet.private : s.id]
}

output "bastion_sg_id" {
  description = "Security group id for bastion"
  value       = aws_security_group.bastion.id
}

output "web_sg_id" {
  description = "Security group id for web instances"
  value       = aws_security_group.web.id
}
