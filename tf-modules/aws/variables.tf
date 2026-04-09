variable "project_name" {
  description = "Used to prefix all resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the k3s node"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key to access the EC2 instance"
  type        = string
  sensitive   = true
}

variable "my_ip" {
  description = "Your public IP in CIDR format (e.g. 1.2.3.4/32)"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
}