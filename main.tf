data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.project_name}-${random_id.bucket_suffix.hex}"
}

module "s3" {
  source       = "./modules/s3"
  bucket_name  = local.bucket_name
  project_name = var.project_name
}
module "iam" {
  source       = "./modules/iam"
  bucket_arn   = module.s3.bucket_arn
  bucket_name  = module.s3.bucket_name
  project_name = var.project_name
}
module "security" {
  source           = "./modules/security"
  vpc_id           = data.aws_vpc.default.id
  project_name     = var.project_name
  enable_ssh       = var.enable_ssh
  ssh_allowed_cidr = var.ssh_allowed_cidr
}
module "ec2" {
  source                = "./modules/ec2"
  project_name          = var.project_name
  instance_type         = var.instance_type
  subnet_id             = data.aws_subnets.default.ids[0]
  security_group_id     = module.security.security_group_id
  instance_profile_name = module.iam.instance_profile_name
  bucket_name           = module.s3.bucket_name
  enable_ssh            = var.enable_ssh
  public_key_path       = var.public_key_path
  root_volume_size      = var.root_volume_size
}
