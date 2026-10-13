output "s3_bucket_name" {
  description = "New S3 bucket name."
  value       = module.s3.bucket_name
}

output "s3_website_endpoint" {
  description = "Public HTTP S3 static website endpoint."
  value       = module.s3.website_endpoint
}

output "ec2_public_ip" {
  description = "Public IPv4 address of the new EC2 instance."
  value       = module.ec2.public_ip
}

output "ec2_instance_id" {
  description = "New EC2 instance ID."
  value       = module.ec2.instance_id
}

output "ec2_url" {
  description = "EC2-hosted Nginx portfolio URL."
  value       = "http://${module.ec2.public_ip}"
}


output "aws_region" {
  description = "AWS region used by this deployment."
  value       = var.aws_region
}
