resource "aws_instance" "web" {
  count = 2
  ami           = var.ami_id
  instance_type = "t3.micro"

  tags = {
    Name = "my-test-instance-${count.index}"
  }
}
