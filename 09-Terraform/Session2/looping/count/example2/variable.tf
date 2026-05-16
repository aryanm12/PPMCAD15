variable "ami_id" {
    type = string
    default = "ami-0866a3c8686eaeeba"
}

variable "instance_name" {
    type = list(string)
    default = ["web-server", "data-server", "backend-server" ]
}

variable "instance_type" {
    type = list(string)
    default = ["t3.micro", "t4.large", "c4.xlarge"]
}