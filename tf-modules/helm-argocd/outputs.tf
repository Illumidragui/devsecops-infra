output "argocd_release_status" {
  description = "Status of the ArgoCD Helm release"
  value       = var.create ? helm_release.argo-cd[0].status : null
}
