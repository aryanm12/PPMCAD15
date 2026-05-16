resource "aws_instance" "web" {
  for_each = var.instance
  ami           = each.value.ami_id
  instance_type = each.value.instance_type
  availability_zone = each.value.availability_zone
  tags = {
    Name = each.key
  }
}
