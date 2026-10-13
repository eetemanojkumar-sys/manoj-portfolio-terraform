variable "vpc_id" { type = string }
variable "project_name" { type = string }
variable "enable_ssh" { type = bool }
variable "ssh_allowed_cidr" {
  type = string
  nullable = true
  default = null
}
