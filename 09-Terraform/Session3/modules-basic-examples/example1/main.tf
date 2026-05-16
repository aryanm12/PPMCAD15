module "my_ec2" {
    source = "./modules/ec2"
    ami_id = "ami-00d8fc944fb171e29"
    sg_ids = [module.security_group.sg_id]
    instance_type = "t3.micro"
    instance_name = "test-instance-01"
}

module "security_group" {
    source = "./modules/sg"
}