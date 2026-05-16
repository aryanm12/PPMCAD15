output "Public_IP" {
    value = aws_instance.ubuntu.public_ip
}

output "instance_arn" {
    value = aws_instance.ubuntu.arn
}