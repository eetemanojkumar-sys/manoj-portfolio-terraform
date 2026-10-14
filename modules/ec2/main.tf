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
    set -Eeuo pipefail
    exec > >(tee -a /var/log/portfolio-bootstrap.log) 2>&1
    trap 'rc=$?; echo "ERROR: bootstrap failed at line $LINENO (exit $rc)"' ERR
    export DEBIAN_FRONTEND=noninteractive

    echo "Starting portfolio EC2 bootstrap: $(date -Is)"

    # Install packages available in Ubuntu 24.04. Do not install awscli via apt:
    # its package may be unavailable on the selected Ubuntu AMI.
    apt-get update
    apt-get install -y nginx snapd curl unzip

    # Install AWS CLI v2 using the official AWS installer.
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip
    aws --version

    # Keep HTTP available while SSM and the initial S3 sync start.
    mkdir -p /var/www/html
    cat > /var/www/html/index.html <<'HTML'
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Portfolio setup in progress</title></head>
    <body><h1>Portfolio server is running</h1><p>Website deployment is initializing. Please refresh shortly.</p></body>
    </html>
    HTML
    systemctl enable --now nginx

    # Install and start SSM Agent for management without SSH.
    snap install amazon-ssm-agent --classic
    systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service
    systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent.service

    # Wait for IAM permissions and the website objects to become available.
    SYNCED=false
    for attempt in $(seq 1 30); do
      if aws s3 sync "s3://${var.bucket_name}/" /var/www/html/ --region ${data.aws_region.current.name} --delete; then
        echo "S3 website sync succeeded on attempt $attempt"
        SYNCED=true
        break
      fi
      echo "S3 sync attempt $attempt failed; retrying in 10 seconds"
      sleep 10
    done
    if [ "$SYNCED" != "true" ]; then
      echo "WARNING: Initial S3 sync did not succeed; Jenkins deployment can retry after SSM is online."
    fi

    chown -R www-data:www-data /var/www/html
    find /var/www/html -type d -exec chmod 755 {} +
    find /var/www/html -type f -exec chmod 644 {} +
    nginx -t
    systemctl reload nginx
    echo "Portfolio EC2 bootstrap completed: $(date -Is)"
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
