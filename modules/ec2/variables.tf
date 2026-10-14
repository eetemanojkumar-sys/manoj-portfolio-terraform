variable "project_name" { type = string }
variable "instance_type" { type = string }
variable "subnet_id" { type = string }
variable "security_group_id" { type = string }
variable "instance_profile_name" { type = string }
variable "bucket_name" { type = string }
variable "enable_ssh" { type = bool }
variable "public_key_path" {
  type     = string
  nullable = true
  default  = null
}
variable "root_volume_size" { type = number }
