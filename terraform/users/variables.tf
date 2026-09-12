variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-northeast-1"
}

variable "users_file" {
  description = "Path to the declarative users YAML file."
  type        = string
  default     = "../../config/users.yaml"
}

variable "efs_file_system_id" {
  description = "Shared EFS filesystem ID used for persistent user homes."
  type        = string
}

variable "instance_id" {
  description = "Shared Ubuntu EC2 instance managed through SSM."
  type        = string
}

variable "local_container_root" {
  description = "EBS-backed root for per-user rootless Podman graphroot/cache."
  type        = string
  default     = "/var/lib/claude-users"
}

variable "home_root" {
  description = "Base mount path for user EFS homes."
  type        = string
  default     = "/home"
}

variable "common_tags" {
  description = "Tags applied to per-user AWS resources."
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    System    = "aws-closed-automation"
  }
}
