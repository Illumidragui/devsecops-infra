# === AWS Infrastructure ===
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Used to prefix all resource names for easy identification"
  type        = string
  default     = "devsecops"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# === EC2 / k3s ===
variable "instance_type" {
  description = "EC2 instance type for the k3s node"
  type        = string
  default     = "t3.medium"
}

variable "ssh_public_key" {
  description = "SSH public key (for backup access via Tailscale)"
  type        = string
  sensitive   = true
}

# === Tailscale ===
variable "tailscale_authkey" {
  description = "Tailscale pre-auth key for the EC2 node (https://login.tailscale.com/admin/settings/keys)"
  type        = string
  sensitive   = true
}

variable "tailscale_hostname" {
  description = "Hostname for the EC2 node in the Tailscale network"
  type        = string
  default     = "lab-kubernetes"
}

variable "tailscale_oauth_clientid" {
  description = "Tailscale OAuth client ID for the in-cluster operator"
  type        = string
  sensitive   = true
  default     = null
}

variable "tailscale_oauth_secret" {
  description = "Tailscale OAuth client secret for the in-cluster operator"
  type        = string
  sensitive   = true
  default     = null
}

# === ArgoCD ===
variable "argocd_admin_password_hash" {
  description = "Bcrypt hash of the ArgoCD admin password"
  type        = string
  sensitive   = true
}

variable "argocd_github_repo" {
  description = "GitHub repo URL for the App of Apps pattern"
  type        = string
  default     = "https://github.com/Illumidragui/argocd-app-of-apps"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file for the k3s cluster"
  type        = string
  default     = "~/.kube/devsecops-config"
}
