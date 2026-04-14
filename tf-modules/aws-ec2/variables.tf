variable "create" {
  description = "Whether to create the EC2 instance and related resources"
  type        = bool
  default     = true
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_type" {
  description = "EC2 instance type for the k3s node"
  type        = string
  default     = "t2.micro"
}

variable "ssh_public_key" {
  description = "SSH public key (for backup access via Tailscale)"
  type        = string
  sensitive   = true
}

variable "subnet_id" {
  description = "Private subnet ID where the EC2 instance will be placed"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the security group"
  type        = string
}

variable "tailscale_authkey" {
  description = "Tailscale pre-auth key for the EC2 node (https://login.tailscale.com/admin/settings/keys)"
  type        = string
  sensitive   = true
}

variable "tailscale_hostname" {
  description = "Hostname for the EC2 node in the Tailscale network"
  type        = string
  default     = "k3s-devsecops"
}
