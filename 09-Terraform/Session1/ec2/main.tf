resource "aws_instance" "ubuntu" {
  ami           = "ami-01938df366ac2d954"
  instance_type = "t3.micro"
  subnet_id     = "subnet-01ed811e6bd6d7965"
  key_name      = "demo-01"

  tags = {
    Name = "my-ubuntu-instance1-hvd"
  }
}