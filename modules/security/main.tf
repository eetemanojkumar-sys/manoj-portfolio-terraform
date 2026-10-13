resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Portfolio HTTP and optional restricted SSH"
  vpc_id      = var.vpc_id

  ingress {
    description = "Public HTTP portfolio"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      description = "SSH from configured trusted IP"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_allowed_cidr]
    }
  }

  egress {
    description = "Outbound package, S3 and SSM HTTPS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = !var.enable_ssh || var.ssh_allowed_cidr != null
      error_message = "Set ssh_allowed_cidr to a trusted public IP CIDR when SSH is enabled."
    }
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}
