output "bastion_id" {
  description = "Instance ID of bastion"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IP of bastion"
  value       = aws_instance.bastion.public_ip
}

output "web_id" {
  description = "Instance ID of web server"
  value       = aws_instance.web.id
}

output "web_private_ip" {
  description = "Private IP of web server"
  value       = aws_instance.web.private_ip
}
