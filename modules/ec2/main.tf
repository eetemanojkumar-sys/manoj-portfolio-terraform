data "aws_region" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_key_pair" "portfolio" {
  count      = var.enable_ssh ? 1 : 0
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.public_key_path))
}

locals {
  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail
    exec > >(tee -a /var/log/portfolio-bootstrap.log) 2>&1
    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y nginx awscli
    systemctl enable --now nginx

    # Ubuntu cloud images may use snap-based SSM Agent; install if not already present.
    if ! systemctl list-unit-files | grep -q 'snap.amazon-ssm-agent'; then
      snap install amazon-ssm-agent --classic || true
    fi
    systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || true

    mkdir -p /var/www/html
    for attempt in $(seq 1 20); do
      if aws s3 sync "s3://${var.bucket_name}/" /var/www/html/ --region ${data.aws_region.current.name} --delete; then
        break
      fi
      sleep 15
    done

    chown -R www-data:www-data /var/www/html
    find /var/www/html -type d -exec chmod 755 {} +
    find /var/www/html -type f -exec chmod 644 {} +
    systemctl reload nginx
  USERDATA
}

resource "aws_instance" "portfolio" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.instance_profile_name
  associate_public_ip_address = true
  key_name                    = var.enable_ssh ? aws_key_pair.portfolio[0].key_name : null
  user_data                   = local.user_data

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.project_name}-ec2"
  }
}
