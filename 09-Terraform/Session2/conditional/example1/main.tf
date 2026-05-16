resource "aws_instance" "web" {
  count = var.enable_instance == true ? 1 : 0
  ami           = var.ami_id
  instance_type = "t3.micro"

  tags = {
    Name = "my-test-instance"
  }
}
