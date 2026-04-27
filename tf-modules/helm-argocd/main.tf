provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# Tailscale operator namespace + OAuth secret (optional — only if credentials are provided)
resource "kubernetes_namespace_v1" "tailscale" {
  count = var.create && var.tailscale_oauth_clientid != null && var.tailscale_oauth_secret != null ? 1 : 0

  metadata {
    name = "tailscale-operator"
  }
}

resource "kubernetes_secret_v1" "tailscale_operator_oauth" {
  count = var.create && var.tailscale_oauth_clientid != null && var.tailscale_oauth_secret != null ? 1 : 0

  metadata {
    name      = "operator-oauth"
    namespace = kubernetes_namespace_v1.tailscale[0].metadata[0].name
  }

  data = {
    client_id     = var.tailscale_oauth_clientid
    client_secret = var.tailscale_oauth_secret
  }
}

# ingress-nginx Helm release
# https://kubernetes.github.io/ingress-nginx
resource "helm_release" "ingress_nginx" {
  count = var.create ? 1 : 0

  name             = "ingress-nginx"
  chart            = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  version          = "4.10.1"
  create_namespace = true
  namespace        = "ingress-nginx"

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
}

# ArgoCD Helm release
# https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd
resource "helm_release" "argo-cd" {
  count = var.create ? 1 : 0

  name             = "argo-cd"
  chart            = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  version          = "7.7.0"
  create_namespace = true
  namespace        = var.namespace

  values = [
    templatefile("${path.module}/helm-values/argo-cd_values.yaml", {
      namespace                  = var.namespace
      argocd_admin_password_hash = var.argocd_admin_password_hash
    })
  ]
}

# ArgoCD App of Apps Helm release
# https://github.com/argoproj/argo-helm/tree/main/charts/argocd-apps
resource "helm_release" "argocd-apps" {
  count = var.create ? 1 : 0

  name             = "argocd-apps"
  chart            = "argocd-apps"
  repository       = "https://argoproj.github.io/argo-helm"
  version          = "2.0.4"
  create_namespace = true
  namespace        = var.namespace

  values = [
    templatefile("${path.module}/helm-values/app-of-apps.yaml", {
      namespace          = var.namespace
      argocd_github_repo = var.argocd_github_repo
    })
  ]

  depends_on = [helm_release.argo-cd]
}
