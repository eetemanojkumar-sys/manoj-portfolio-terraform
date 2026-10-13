variable "aws_region" {
  description = "AWS region in which to create the new portfolio resources."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short lowercase project prefix."
  type        = string
  default     = "manoj-portfolio"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Use lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "portfolio"
}

variable "instance_type" {
  description = "EC2 instance type. Check current regional pricing and eligibility."
  type        = string
  default     = "t3.micro"
}

variable "enable_ssh" {
  description = "Whether to allow SSH access to the instance."
  type        = bool
  default     = true
}

variable "ssh_allowed_cidr" {
  description = "Your public IP in CIDR notation, such as 203.0.113.10/32. Required when SSH is enabled."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.ssh_allowed_cidr == null || can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR block."
  }
}

variable "public_key_path" {
  description = "Path to an SSH public key. Required only when enable_ssh=true."
  type        = string
  default     = null
  nullable    = true
}

variable "root_volume_size" {
  description = "EC2 root volume size in GiB."
  type        = number
  default     = 10
}
