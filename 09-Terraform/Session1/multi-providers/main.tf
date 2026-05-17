resource "aws_instance" "web" {
  ami           = "ami-07a00cf47dbbc844c"  # search for latest ubuntu ami id from your region and replace xxx with it
  instance_type = "t3.small"               # Free tier eligible
  subnet_id = "subnet-0e6e6d4790468ad96"
  tags = {
    Name = "MyTerraformWebServer"
    Environment = "dev"
  }
}

resource "aws_instance" "web-personal" {
  provider = aws.account_personal
  ami           = "ami-07a00cf47dbbc844c"  # search for latest ubuntu ami id from your region and replace xxx with it
  instance_type = "t3.small"               # Free tier eligible
  subnet_id = "subnet-005fc125b7a794efb"
  tags = {
    Name = "MyTerraformWebServer"
    Environment = "dev"
  }
}