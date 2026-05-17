variable "ami_id_demo" {
  type = string
}

variable "instance_type_demo" {
  type = string
  default = "t3.medium"
}

variable "subnet_id_demo" {
  type = string
}

variable "tags_demo" {
  type = map(any)
}