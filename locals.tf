locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  k3s_ports = {
    ssh = 22
    api = 6443
  }
}