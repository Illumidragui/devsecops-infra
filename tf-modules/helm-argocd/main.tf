# tf-modules/k8s-platform/main.tf
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "7.7.0"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "NodePort"
  }
}