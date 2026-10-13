variable "aws_region" {
  description = "Region for new portfolio resources."
  type = string
  default = "ap-south-1"
}
variable "project_name" {
  description = "Lowercase resource prefix."
  type = string
  default = "manoj-portfolio"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Use lowercase letters, numbers and hyphens only."
  }
}
variable "environment" {
  type = string
  default = "portfolio"
}
variable "instance_type" {
  type = string
  default = "t3.micro"
}
variable "enable_ssh" {
  description = "Enable optional SSH restricted to ssh_allowed_cidr. SSM remains available."
  type = bool
  default = false
}
variable "ssh_allowed_cidr" {
  description = "Trusted public IPv4 CIDR (for example x.x.x.x/32) when SSH is enabled."
  type = string
  nullable = true
  default = null
  validation {
    condition = var.ssh_allowed_cidr == null || can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR block."
  }
}
variable "public_key_path" {
  description = "Path to an SSH public key file; only required when enable_ssh=true."
  type = string
  nullable = true
  default = null
}
variable "root_volume_size" {
  type = number
  default = 10
}
