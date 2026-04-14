variable "create" {
  description = "Whether to create the VPC and networking resources"
  type        = bool
  default     = true
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}
