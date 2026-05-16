resource "aws_security_group" "allow_tls" {
  name        = "allow_tls_module"
  description = "Allow TLS inbound traffic and all outbound traffic"
  tags = {
    Name = "allow_tls"
  }
}
