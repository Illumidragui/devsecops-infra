variable "create" {
  description = "Whether to deploy ArgoCD and related Helm releases"
  type        = bool
  default     = false
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file for the k3s cluster"
  type        = string
  default     = "~/.kube/devsecops-config"
}

variable "namespace" {
  description = "Kubernetes namespace where ArgoCD will be deployed"
  type        = string
  default     = "argo-cd"
}

variable "argocd_github_repo" {
  description = "GitHub repo URL for the App of Apps ArgoCD Application"
  type        = string
}

variable "argocd_admin_password_hash" {
  description = "Bcrypt hash of the ArgoCD admin password (store plaintext in GitHub Actions secret, hash locally)"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_clientid" {
  description = "Tailscale OAuth client ID for the in-cluster operator (optional)"
  type        = string
  sensitive   = true
  default     = null
}

variable "tailscale_oauth_secret" {
  description = "Tailscale OAuth client secret for the in-cluster operator (optional)"
  type        = string
  sensitive   = true
  default     = null
}
