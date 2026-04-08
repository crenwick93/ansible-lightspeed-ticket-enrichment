variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "allowed_cidr" {
  description = "CIDR block allowed to reach the instance (SSH, HTTP, Prometheus, etc.)"
  type        = string
  default     = "0.0.0.0/0"
}
