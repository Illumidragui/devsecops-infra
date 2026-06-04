#!/usr/bin/env bash
# deploy.sh — Provision VPC + EC2 + EIP and wait for k3s.
# After this completes, run bootstrap-argocd.sh to install ArgoCD.
#
# Prerequisites:
#   aws CLI configured (aws configure / SSO / env vars)
#   terraform >= 1.0
#   tailscale CLI (optional — needed if connecting via Tailnet)
#   ssh + scp
#
# Required env vars (or set as TF_VAR_* in your shell):
#   TF_VAR_ssh_public_key    — contents of your SSH public key
#   TF_VAR_tailscale_authkey — Tailscale pre-auth key for the EC2 node
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[deploy]${NC} $*"; }
warn()  { echo -e "${YELLOW}[deploy]${NC} $*"; }
error() { echo -e "${RED}[deploy]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/devsecops-config}"
TS_HOSTNAME="${TS_HOSTNAME:-lab-kubernetes}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/devsecops_deploy}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i ${SSH_KEY}"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
command -v terraform >/dev/null || error "terraform not found"
command -v aws       >/dev/null || error "aws CLI not found"
aws sts get-caller-identity --query Arn --output text >/dev/null 2>&1 \
  || error "No valid AWS credentials. Run 'aws configure' or set env vars."

[[ -n "${TF_VAR_ssh_public_key:-}" ]]    || error "TF_VAR_ssh_public_key is not set"
[[ -n "${TF_VAR_tailscale_authkey:-}" ]] || error "TF_VAR_tailscale_authkey is not set"

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

info "Applying — VPC, EC2, EIP..."
terraform apply -auto-approve -input=false \
  -target=module.vpc \
  -target=module.ec2 \
  -target=aws_eip.k3s \
  -target=aws_eip_association.k3s

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
info "Done. Next step: run scripts/bootstrap-argocd.sh"
