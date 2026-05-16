variable "instance" {
  default = {
    "web-server" = {
        ami_id = "ami-0866a3c8686eaeeba"
        instance_type = "t3.micro"
        availability_zone = "us-east-1a"
    },
    "data-server" = {
        ami_id = "ami-0866a3c8686eaeeba"
        instance_type = "t2.micro"
        availability_zone = "us-east-1b"
    },
    "web-server-2" = {
        ami_id = "ami-0866a3c8686eaeeba"
        instance_type = "t4.micro"
        availability_zone = "us-east-1a"
    },
    "data-server-2" = {
        ami_id = "ami-0866a3c8686eaeeba"
        instance_type = "t2.micro"
        availability_zone = "us-east-1b"
    }
  }
  type = map(object({
    ami_id = string
    instance_type = string
    availability_zone = string
  }))
}