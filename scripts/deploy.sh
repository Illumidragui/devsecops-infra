#!/usr/bin/env bash
# deploy.sh — Provision VPC + EC2 + EIP, wait for k3s, then auto-bootstrap ArgoCD.
#
# Prerequisites:
#   aws CLI configured (aws configure / SSO / env vars)
#   terraform >= 1.0
#   tailscale CLI (optional — needed if connecting via Tailnet)
#   ssh + scp
#   kubectl, helm >= 3.0 — required for the bootstrap-argocd.sh hand-off at the end
#
# Required env vars (or set as TF_VAR_* in your shell):
#   TF_VAR_ssh_public_key         — contents of your SSH public key
#   TF_VAR_tailscale_authkey      — Tailscale pre-auth key for the EC2 node
#   TF_VAR_cloudflare_api_token   — Cloudflare API token (dash.cloudflare.com/profile/api-tokens)
#   ARGOCD_ADMIN_PASSWORD         — plaintext ArgoCD admin password (passed through to bootstrap-argocd.sh)
#
# Optional (passed through to bootstrap-argocd.sh):
#   ARGOCD_GITHUB_REPO, TAILSCALE_OAUTH_CLIENTID, TAILSCALE_OAUTH_SECRET
#
# Set SKIP_ARGOCD_BOOTSTRAP=true to stop after infra + kubeconfig, as before.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[deploy]${NC} $*"; }
warn()  { echo -e "${YELLOW}[deploy]${NC} $*"; }
error() { echo -e "${RED}[deploy]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/devsecops-config}"
TS_HOSTNAME="${TS_HOSTNAME:-lab-kubernetes}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/deploy_key}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i ${SSH_KEY}"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
command -v terraform >/dev/null || error "terraform not found"
command -v aws       >/dev/null || error "aws CLI not found"
aws sts get-caller-identity --query Arn --output text >/dev/null 2>&1 \
  || error "No valid AWS credentials. Run 'aws configure' or set env vars."

[[ -n "${TF_VAR_ssh_public_key:-}" ]]       || error "TF_VAR_ssh_public_key is not set"
[[ -n "${TF_VAR_tailscale_authkey:-}" ]]    || error "TF_VAR_tailscale_authkey is not set"
[[ -n "${TF_VAR_cloudflare_api_token:-}" ]] || error "TF_VAR_cloudflare_api_token is not set"

SKIP_ARGOCD_BOOTSTRAP="${SKIP_ARGOCD_BOOTSTRAP:-false}"
if [[ "${SKIP_ARGOCD_BOOTSTRAP}" != "true" ]]; then
  command -v kubectl >/dev/null || error "kubectl not found (required for the ArgoCD bootstrap hand-off; set SKIP_ARGOCD_BOOTSTRAP=true to skip it)"
  command -v helm    >/dev/null || error "helm not found (required for the ArgoCD bootstrap hand-off; set SKIP_ARGOCD_BOOTSTRAP=true to skip it)"
  [[ -n "${ARGOCD_ADMIN_PASSWORD:-}" ]] || error "ARGOCD_ADMIN_PASSWORD is not set (required for the ArgoCD bootstrap hand-off; set SKIP_ARGOCD_BOOTSTRAP=true to skip it)"
fi

USE_TAILSCALE=false
if command -v tailscale >/dev/null 2>&1; then
  USE_TAILSCALE=true
else
  warn "tailscale CLI not found — kubeconfig copy will use public IP instead"
fi

# ── Terraform apply ───────────────────────────────────────────────────────────
cd "$INFRA_DIR"
info "Initialising Terraform..."
terraform init -input=false

info "Applying — VPC, EC2, EIP, DNS..."
terraform apply -auto-approve -input=false \
  -target=module.vpc \
  -target=module.ec2 \
  -target=aws_eip.k3s \
  -target=aws_eip_association.k3s \
  -target=cloudflare_dns_record.hello \
  -target=cloudflare_dns_record.kuberflow

PUBLIC_IP=$(terraform output -raw public_ip)
info "EC2 provisioned. EIP: ${PUBLIC_IP}"

# ── Wait for k3s ─────────────────────────────────────────────────────────────
if $USE_TAILSCALE; then
  info "Waiting for ${TS_HOSTNAME} to appear in Tailnet (up to 5 min)..."
  for i in $(seq 1 20); do
    NODE_IP=$(tailscale ip -4 "${TS_HOSTNAME}" 2>/dev/null) || true
    [[ -n "${NODE_IP}" ]] && { info "Node visible at ${NODE_IP} (Tailscale)"; break; }
    [[ $i -eq 20 ]] && error "Timed out waiting for node in Tailnet"
    warn "Attempt $i/20 — retrying in 15s"
    sleep 15
  done
else
  NODE_IP="${PUBLIC_IP}"
  info "Using public IP ${NODE_IP} for SSH"
fi

info "Waiting for k3s to be Ready (up to 10 min)..."
for i in $(seq 1 40); do
  if ssh $SSH_OPTS "ec2-user@${NODE_IP}" \
      "sudo kubectl get nodes --no-headers 2>/dev/null" 2>/dev/null \
      | grep -q "Ready"; then
    info "k3s Ready after attempt $i"
    break
  fi
  [[ $i -eq 40 ]] && error "Timed out waiting for k3s"
  warn "Attempt $i/40 — retrying in 15s"
  sleep 15
done

# ── Copy kubeconfig ───────────────────────────────────────────────────────────
mkdir -p "$(dirname "$KUBECONFIG_PATH")"
scp $SSH_OPTS "ec2-user@${NODE_IP}:/etc/rancher/k3s/k3s.yaml" "$KUBECONFIG_PATH"
sed -i "s/127.0.0.1/${NODE_IP}/g" "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"

info "Kubeconfig written to ${KUBECONFIG_PATH}"

if [[ "${SKIP_ARGOCD_BOOTSTRAP}" == "true" ]]; then
  info "SKIP_ARGOCD_BOOTSTRAP=true — done. Next step: run scripts/bootstrap-argocd.sh"
else
  info "Handing off to bootstrap-argocd.sh..."
  KUBECONFIG_PATH="${KUBECONFIG_PATH}" "${SCRIPT_DIR}/bootstrap-argocd.sh"
fi
