# VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge({
    Name = "${var.env}-vpc"
    Env  = var.env
  }, var.tags)
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = merge({ Name = "${var.env}-igw", Env = var.env }, var.tags)
}

# Public subnets (for_each keyed by index string "0","1",...)
resource "aws_subnet" "public" {
  for_each = { for idx, cidr in var.public_subnet_cidrs : tostring(idx) => cidr }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = merge({
    Name = "${var.env}-public-${each.key}"
    Env  = var.env
  }, var.tags)
}

# Private subnets
resource "aws_subnet" "private" {
  for_each = { for idx, cidr in var.private_subnet_cidrs : tostring(idx) => cidr }

  vpc_id     = aws_vpc.this.id
  cidr_block = each.value

  tags = merge({
    Name = "${var.env}-private-${each.key}"
    Env  = var.env
  }, var.tags)
}

# Public Route Table + association to public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge({ Name = "${var.env}-public-rt", Env = var.env }, var.tags)
}

resource "aws_route_table_association" "public_assoc" {
  for_each = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway (single NAT in first public subnet) + EIP
resource "aws_eip" "nat" {
  depends_on = [aws_internet_gateway.igw]
  tags = merge({ Name = "${var.env}-nat-eip", Env = var.env }, var.tags)
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[tostring(0)].id
  tags = merge({ Name = "${var.env}-nat", Env = var.env }, var.tags)
}

# Private route table -> NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge({ Name = "${var.env}-private-rt", Env = var.env }, var.tags)
}

resource "aws_route_table_association" "private_assoc" {
  for_each = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# Security groups
resource "aws_security_group" "bastion" {
  name   = "${var.env}-bastion-sg"
  vpc_id = aws_vpc.this.id
  description = "Allow SSH to bastion (lock in prod via tfvars)"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # override in env tfvars for prod
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "${var.env}-bastion-sg", Env = var.env }, var.tags)
}

resource "aws_security_group" "web" {
  name   = "${var.env}-web-sg"
  vpc_id = aws_vpc.this.id
  description = "Allow HTTP and SSH from bastion"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "${var.env}-web-sg", Env = var.env }, var.tags)
}
