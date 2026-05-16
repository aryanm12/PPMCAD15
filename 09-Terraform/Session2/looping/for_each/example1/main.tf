resource "aws_instance" "web" {
  for_each = var.instance
  ami           = var.ami_id
  instance_type = each.value

  tags = {
    Name = each.key
  }
}
