#!/usr/bin/env bash
# bootstrap-argocd.sh — Install ArgoCD + App of Apps on a running k3s cluster.
# Run this after deploy.sh. Safe to re-run (Helm upgrades existing releases).
#
# Prerequisites:
#   kubectl configured (KUBECONFIG or default ~/.kube/devsecops-config)
#   helm >= 3.0
#   ARGOCD_ADMIN_PASSWORD  — plaintext admin password (bcrypt hash generated here)
#   ARGOCD_GITHUB_REPO     — App of Apps repo (default: Illumidragui/argocd-app-of-apps)
#
# Optional:
#   TAILSCALE_OAUTH_CLIENTID / TAILSCALE_OAUTH_SECRET — exposes ArgoCD UI via Tailscale
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[bootstrap]${NC} $*"; }
warn()  { echo -e "${YELLOW}[bootstrap]${NC} $*"; }
error() { echo -e "${RED}[bootstrap]${NC} $*" >&2; exit 1; }

KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/devsecops-config}"
ARGOCD_NS="${ARGOCD_NS:-argo-cd}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.7.0}"
ARGOCD_APPS_CHART_VERSION="${ARGOCD_APPS_CHART_VERSION:-2.0.4}"
ARGOCD_GITHUB_REPO="${ARGOCD_GITHUB_REPO:-https://github.com/Illumidragui/argocd-app-of-apps}"

export KUBECONFIG="${KUBECONFIG_PATH}"

# ── Pre-flight ────────────────────────────────────────────────────────────────
command -v kubectl >/dev/null || error "kubectl not found"
command -v helm    >/dev/null || error "helm >= 3 not found"
kubectl cluster-info >/dev/null 2>&1 || error "Cannot reach cluster. Check KUBECONFIG (${KUBECONFIG_PATH})"

[[ -n "${ARGOCD_ADMIN_PASSWORD:-}" ]] || error "ARGOCD_ADMIN_PASSWORD is not set"

# Generate bcrypt hash — use htpasswd if available, otherwise python
if command -v htpasswd >/dev/null 2>&1; then
  ARGOCD_ADMIN_HASH=$(htpasswd -bnBC 10 "" "${ARGOCD_ADMIN_PASSWORD}" | tr -d ':\n' | sed 's/$2y/$2a/')
elif command -v python3 >/dev/null 2>&1 && python3 -c "import bcrypt" 2>/dev/null; then
  ARGOCD_ADMIN_HASH=$(python3 -c \
    "import bcrypt; print(bcrypt.hashpw(b'${ARGOCD_ADMIN_PASSWORD}', bcrypt.gensalt(rounds=10)).decode())")
else
  error "Need htpasswd (apache2-utils) or python3+bcrypt to hash the password"
fi

# ── Helm repos ────────────────────────────────────────────────────────────────
info "Adding Helm repos..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

# ── Namespace ─────────────────────────────────────────────────────────────────
kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f -

# ── Tailscale secret (optional) ───────────────────────────────────────────────
TAILSCALE_VALUES=""
if [[ -n "${TAILSCALE_OAUTH_CLIENTID:-}" && -n "${TAILSCALE_OAUTH_SECRET:-}" ]]; then
  info "Creating Tailscale operator secret..."
  kubectl create namespace tailscale-operator --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic operator-oauth \
    --namespace tailscale-operator \
    --from-literal=client_id="${TAILSCALE_OAUTH_CLIENTID}" \
    --from-literal=client_secret="${TAILSCALE_OAUTH_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f -
  TAILSCALE_VALUES='--set "server.service.annotations.tailscale\.com/expose=true"'
fi

# ── ArgoCD install ────────────────────────────────────────────────────────────
info "Installing ArgoCD ${ARGOCD_CHART_VERSION}..."
# shellcheck disable=SC2086
helm upgrade --install argo-cd argo/argo-cd \
  --namespace "${ARGOCD_NS}" \
  --version "${ARGOCD_CHART_VERSION}" \
  --set crds.install=true \
  --set namespaceOverride="${ARGOCD_NS}" \
  --set configs.secret.argocdServerAdminPassword="${ARGOCD_ADMIN_HASH}" \
  --set server.extraArgs[0]="--insecure" \
  --set redis.resources.requests.memory=64Mi \
  --set redis.resources.requests.cpu=50m \
  --set controller.resources.requests.memory=128Mi \
  --set controller.resources.requests.cpu=100m \
  --set repoServer.resources.requests.memory=64Mi \
  --set repoServer.resources.requests.cpu=50m \
  ${TAILSCALE_VALUES} \
  --wait --timeout 5m

info "ArgoCD installed. Waiting for server to be ready..."
kubectl rollout status deployment/argo-cd-argocd-server -n "${ARGOCD_NS}" --timeout=3m

# ── App of Apps bootstrap ─────────────────────────────────────────────────────
info "Bootstrapping App of Apps from ${ARGOCD_GITHUB_REPO}..."
helm upgrade --install argocd-apps argo/argocd-apps \
  --namespace "${ARGOCD_NS}" \
  --version "${ARGOCD_APPS_CHART_VERSION}" \
  --set "applications.app-of-apps.namespace=${ARGOCD_NS}" \
  --set "applications.app-of-apps.project=default" \
  --set "applications.app-of-apps.source.repoURL=${ARGOCD_GITHUB_REPO}" \
  --set "applications.app-of-apps.source.targetRevision=main" \
  --set "applications.app-of-apps.source.path=." \
  --set "applications.app-of-apps.destination.server=https://kubernetes.default.svc" \
  --set "applications.app-of-apps.destination.namespace=${ARGOCD_NS}" \
  --set "applications.app-of-apps.syncPolicy.automated.prune=true" \
  --set "applications.app-of-apps.syncPolicy.automated.selfHeal=true" \
  --wait --timeout 2m

info "Bootstrap complete."
info ""
info "ArgoCD admin UI:"
info "  Port-forward: kubectl port-forward svc/argo-cd-argocd-server -n ${ARGOCD_NS} 8080:80"
info "  URL: http://localhost:8080  |  user: admin  |  pass: \${ARGOCD_ADMIN_PASSWORD}"
if [[ -n "${TAILSCALE_OAUTH_CLIENTID:-}" ]]; then
  info "  Tailscale: https://lab-kubernetes (once operator syncs)"
fi
info ""
info "ArgoCD will now auto-sync all applications from Git. Check status:"
info "  kubectl get applications -n ${ARGOCD_NS}"
