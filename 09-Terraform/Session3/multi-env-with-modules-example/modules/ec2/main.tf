# Bastion host (public subnet)
resource "aws_instance" "bastion" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_ids[0]
  key_name               = var.bastion_key_name
  vpc_security_group_ids = [var.bastion_sg_id]

  associate_public_ip_address = true

  tags = merge({
    Name = "${var.env}-bastion"
    Env  = var.env
  }, var.tags)
}

# Web instance (private subnet)
resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.web_sg_id]
  associate_public_ip_address = false

  # simple user-data to serve a test page
  user_data = <<-EOF
              #!/bin/bash
              set -e
              # Example for Amazon Linux 2; update package manager as needed for other distros
              if command -v yum &> /dev/null; then
                yum update -y
                yum install -y httpd
                systemctl enable httpd
                systemctl start httpd
              elif command -v apt-get &> /dev/null; then
                apt-get update -y
                apt-get install -y apache2
                systemctl enable apache2
                systemctl start apache2
              fi
              echo "Hello from ${var.env} web instance" > /var/www/html/index.html
              EOF

  tags = merge({
    Name = "${var.env}-web"
    Env  = var.env
  }, var.tags)
}
