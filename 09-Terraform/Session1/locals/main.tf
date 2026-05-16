data "aws_vpc" "example" {
  filter {
    name   = "tag:name"
    values = ["default_vpc"]
  }
}

locals {
  common_prefix = "${var.account}-${var.environment}"
}

resource "aws_subnet" "public_subnet1" {
  vpc_id     = data.aws_vpc.example.id
  cidr_block = "172.31.128.0/28"

  tags = {
    Name = "${local.common_prefix}-pub-subnet1"
  }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id     = data.aws_vpc.example.id
  cidr_block = "172.31.196.0/28"

  tags = {
    Name = "${local.common_prefix}-pub-subnet2"
  }
}
