variable "ami_id" {
    type = string
}

variable "instance_type" {
    type = string
}

variable "sg_ids" {
    type = list(string)
}

variable "instance_name" {
    type = string
}