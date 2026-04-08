variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "private_key_path" {
  description = "Local path to the matching SSH private key (used in generated Ansible inventory)"
  type        = string
}

variable "allowed_cidr" {
  description = "CIDR block allowed to reach the instance (SSH, HTTP, Prometheus, etc.)"
  type        = string
  default     = "0.0.0.0/0"
}
