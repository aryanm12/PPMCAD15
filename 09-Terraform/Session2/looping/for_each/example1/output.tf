output "Public_IP" {
    value = [for x in aws_instance.web: x.public_ip]
}