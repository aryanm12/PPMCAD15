output "pub_ip" {
    value = module.my_ec2.Public_IP
}

output "security_group_id" {
    value = module.security_group.sg_id
}