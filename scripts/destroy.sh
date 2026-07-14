#!/usr/bin/env bash
# destroy.sh — Destroy EC2 + EIP association. VPC and EIP allocation are kept.
# EIP is preserved so the DNS record (shengjunye.me → EIP) stays stable.
#
# Prerequisites:
#   aws CLI configured
#   terraform >= 1.0
#   TAILSCALE_API_TOKEN env var (optional — used to deregister device from Tailnet)
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[destroy]${NC} $*"; }
warn()  { echo -e "${YELLOW}[destroy]${NC} $*"; }
error() { echo -e "${RED}[destroy]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
TS_HOSTNAME="${TS_HOSTNAME:-lab-kubernetes}"

# ── Safety prompt ─────────────────────────────────────────────────────────────
echo -e "${RED}WARNING${NC}: This will destroy the EC2 instance and all running workloads."
echo "The EIP allocation and VPC will be preserved."
read -r -p "Type 'destroy' to confirm: " CONFIRM
[[ "${CONFIRM}" == "destroy" ]] || { echo "Aborted."; exit 0; }

# ── Pre-flight ────────────────────────────────────────────────────────────────
command -v terraform >/dev/null || error "terraform not found"
command -v aws       >/dev/null || error "aws CLI not found"
aws sts get-caller-identity --query Arn --output text >/dev/null 2>&1 \
  || error "No valid AWS credentials."

[[ -n "${TF_VAR_ssh_public_key:-}" ]]    || error "TF_VAR_ssh_public_key is not set"
[[ -n "${TF_VAR_tailscale_authkey:-}" ]] || error "TF_VAR_tailscale_authkey is not set"

# Not used here (porkbun_dns_record.* is never targeted) but the provider
# block in versions.tf requires a value or terraform prompts interactively.
export TF_VAR_porkbun_api_key="${TF_VAR_porkbun_api_key:-unused}"
export TF_VAR_porkbun_secret_api_key="${TF_VAR_porkbun_secret_api_key:-unused}"

# ── Remove from Tailscale ─────────────────────────────────────────────────────
if [[ -n "${TAILSCALE_API_TOKEN:-}" ]]; then
  info "Removing ${TS_HOSTNAME} from Tailscale..."
  DEVICE_ID=$(curl -sf \
    -H "Authorization: Bearer ${TAILSCALE_API_TOKEN}" \
    "https://api.tailscale.com/api/v2/tailnet/-/devices" \
    | jq -r --arg h "${TS_HOSTNAME}" '.devices[] | select(.hostname == $h) | .id' \
    2>/dev/null || true)

  if [[ -n "${DEVICE_ID}" ]]; then
    curl -sf -X DELETE \
      -H "Authorization: Bearer ${TAILSCALE_API_TOKEN}" \
      "https://api.tailscale.com/api/v2/device/${DEVICE_ID}" >/dev/null
    info "Removed ${TS_HOSTNAME} (id: ${DEVICE_ID}) from Tailscale"
  else
    warn "Device not found in Tailnet — already removed or was never registered"
  fi
else
  warn "TAILSCALE_API_TOKEN not set — skipping Tailscale device removal"
fi

# ── Terraform destroy ─────────────────────────────────────────────────────────
cd "$INFRA_DIR"
info "Initialising Terraform..."
terraform init -input=false

info "Destroying EIP association + EC2..."
terraform destroy -auto-approve -input=false \
  -target=aws_eip_association.k3s \
  -target=module.ec2

EIP=$(terraform output -raw public_ip 2>/dev/null || echo "(could not read)")
info "EC2 destroyed. EIP allocation preserved: ${EIP}"
info "DNS record for shengjunye.me is still valid."
