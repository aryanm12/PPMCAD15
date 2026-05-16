resource "aws_instance" "web" {
  ami           = var.environment == "prod" ? "ami-122" : "ami-322"
  instance_type = var.environment == "prod" ? "t3.micro" : "t2.micro"

  tags = {
    Name = "my-test-instance"
  }
}