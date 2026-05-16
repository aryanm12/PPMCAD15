resource "aws_instance" "web" {
  count = 2
  ami           = var.ami_id
  instance_type = var.instance_type[count.index]

  tags = {
    Name = var.instance_name[count.index]
  }
}
