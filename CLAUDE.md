# CLAUDE.md — devsecops-infra

GitHub repo: `Illumidragui/devsecops-infra`

Terraform provisions the immutable cloud layer: VPC, EC2 (k3s node), and Elastic IP.
ArgoCD and all Kubernetes workloads are **not** managed here — see `bootstrap-argocd.sh`.

## Root module layout

The root module is split by concern, mirroring the convention already used inside
`tf-modules/aws-vpc/` and `tf-modules/aws-ec2/` (`versions.tf` / `locals.tf` / `main.tf` /
`outputs.tf` / `variables.tf` each own one job):

| File | Contains |
|---|---|
| `versions.tf` | `terraform{}` block, `required_providers`, provider configuration (`aws`, `porkbun`) |
| `backend.tf` | S3 remote state backend |
| `main.tf` | `locals{}` + `module.vpc` / `module.ec2` calls only |
| `eip.tf` | `aws_eip.k3s`, `aws_eip_association.k3s` |
| `dns.tf` | `porkbun_dns_record.*` |
| `variables.tf` | All root input variables |
| `outputs.tf` | All root outputs |

## Module map

| Module / Resource | File | Creates |
|---|---|---|
| `module.vpc` | `tf-modules/aws-vpc/` | VPC 10.0.0.0/16, public + private subnets, NAT GW, IGW |
| `module.ec2` | `tf-modules/aws-ec2/` | EC2 t3.medium, SG, key pair, user_data (k3s + Tailscale) |
| `aws_eip.k3s` | `eip.tf` | Elastic IP — never destroy this resource |
| `aws_eip_association.k3s` | `eip.tf` | Binds EIP to EC2 on each deploy, torn down on destroy |
| `porkbun_dns_record.*` | `dns.tf` | A records (apex, `www`, `hello`, `kuberflow`) for `shengjunye.me`, pointing at `aws_eip.k3s` — never destroy |

## Variables (required at deploy time)

| Variable | Set via | Notes |
|---|---|---|
| `TF_VAR_ssh_public_key` | env var | Content of public key (not path) |
| `TF_VAR_tailscale_authkey` | env var | Pre-auth key from Tailscale admin |
| `TF_VAR_tailscale_hostname` | env var or default | Default: `lab-kubernetes` |
| `TF_VAR_instance_type` | env var or default | Default: `t3.medium` |
| `TF_VAR_porkbun_api_key` | env var | Porkbun API key (porkbun.com/account/api) |
| `TF_VAR_porkbun_secret_api_key` | env var | Porkbun secret API key |

## Local workflow (FinOps — spin up on demand)

```bash
# 1. Provision infra + wait for k3s
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
export TF_VAR_tailscale_authkey="tskey-auth-..."
export TF_VAR_porkbun_api_key="pk1_..."
export TF_VAR_porkbun_secret_api_key="sk1_..."
bash scripts/deploy.sh

# 2. Bootstrap ArgoCD (once per fresh cluster)
export ARGOCD_ADMIN_PASSWORD="your-password"
bash scripts/bootstrap-argocd.sh

# 3. Destroy when done (EIP is preserved)
export TAILSCALE_API_TOKEN="tskey-api-..."
bash scripts/destroy.sh
```

## CI/CD workflow (GitHub Actions)

- **ci-fast.yml** — push to `dev`: gitleaks + terraform lint
- **ci-pr.yml** — PR to `main`: gitleaks + terraform lint + Checkov
- **deploy.yml** — manual `workflow_dispatch`: runs Phase 1 only (VPC + EC2 + EIP + DNS)
- **destroy.yml** — manual `workflow_dispatch`: destroys EC2, preserves EIP + DNS

## Validation commands

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
tflint --recursive
```

## Key invariants — do not break these

- **`aws_eip.k3s` must never be destroyed** — it is the target of the DNS records for `shengjunye.me`
- **`porkbun_dns_record.*` must never be destroyed** — same reasoning as the EIP: they point at a
  stable Elastic IP that survives instance rebuilds, so they belong outside `destroy.sh`/`destroy.yml`
- **No static AWS credentials** — OIDC only in CI; `aws configure` / SSO locally
- **`module.helm-argocd` does not exist** — ArgoCD is bootstrapped via `scripts/bootstrap-argocd.sh`
- **EC2 is in the public subnet** but port 6443 (k3s API) is restricted to VPC CIDR only
- Tailscale is the only external access path to k3s; do not open 6443 to 0.0.0.0/0

## Adding a new variable

1. Add to `variables.tf` with description + type + sensitive flag
2. Wire it up: pass to the relevant module in `main.tf`, or reference it directly in `eip.tf`/`dns.tf`,
   or add to a `provider {}` block in `versions.tf` — wherever it's actually consumed
3. Update `deploy.yml` env block (and `scripts/deploy.sh` required-env-var check) if it's needed
   at deploy time — `destroy.yml`/`destroy.sh` don't touch DNS/EIP so usually don't need it
4. Update this file's variable table

## Oracle Cloud migration notes

When migrating to OCI, replace `tf-modules/aws-vpc/` and `tf-modules/aws-ec2/` with OCI equivalents.
`main.tf` wires modules together and `versions.tf` holds the provider block — only the module sources
and provider change; `eip.tf`/`dns.tf`, the k3s user_data, and everything above the infra layer
(ArgoCD, Helm, scripts) are cloud-agnostic.
