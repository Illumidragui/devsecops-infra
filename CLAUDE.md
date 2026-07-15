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
| `versions.tf` | `terraform{}` block, `required_providers`, provider configuration (`aws`, `cloudflare`) |
| `backend.tf` | S3 remote state backend |
| `main.tf` | `locals{}` + `module.vpc` / `module.ec2` calls only |
| `eip.tf` | `aws_eip.k3s`, `aws_eip_association.k3s` |
| `dns.tf` | `data.cloudflare_zone.shengjunye`, `cloudflare_dns_record.*` |
| `variables.tf` | All root input variables |
| `outputs.tf` | All root outputs |

## Module map

| Module / Resource | File | Creates |
|---|---|---|
| `module.vpc` | `tf-modules/aws-vpc/` | VPC 10.0.0.0/16, public + private subnets, NAT GW, IGW |
| `module.ec2` | `tf-modules/aws-ec2/` | EC2 t3.medium, SG, key pair, user_data (k3s + Tailscale) |
| `aws_eip.k3s` | `eip.tf` | Elastic IP — never destroy this resource |
| `aws_eip_association.k3s` | `eip.tf` | Binds EIP to EC2 on each deploy, torn down on destroy |
| `cloudflare_dns_record.*` | `dns.tf` | A records for `hello`/`kuberflow.shengjunye.me` only, pointing at `aws_eip.k3s` — destroyed by `destroy-all` only. Does **not** include apex/`www` (Cloudflare Pages custom domain, owned by the `website` repo) |

## Variables (required at deploy time)

| Variable | Set via | Notes |
|---|---|---|
| `TF_VAR_ssh_public_key` | env var | Content of public key (not path) |
| `TF_VAR_tailscale_authkey` | env var | Pre-auth key from Tailscale admin |
| `TF_VAR_tailscale_hostname` | env var or default | Default: `lab-kubernetes` |
| `TF_VAR_instance_type` | env var or default | Default: `t3.medium` |
| `TF_VAR_cloudflare_api_token` | env var | Cloudflare API token, scoped to Zone:Read + DNS:Edit on `shengjunye.me` |
| `ARGOCD_ADMIN_PASSWORD` | env var / repo secret | Plaintext ArgoCD admin password, consumed by `bootstrap-argocd.sh` (auto-chained from `deploy.sh`/`deploy.yml`). Skip via `SKIP_ARGOCD_BOOTSTRAP=true` if you don't need it yet |
| `TAILSCALE_OAUTH_CLIENTID` / `TAILSCALE_OAUTH_SECRET` | env var / repo secret | Optional — exposes the ArgoCD UI via `tailscale-operator` |

## Local workflow (FinOps — spin up on demand)

`deploy.sh` provisions infra and then auto-chains into `bootstrap-argocd.sh` once k3s is
`Ready` — one command takes you from nothing to a synced ArgoCD. Set
`SKIP_ARGOCD_BOOTSTRAP=true` to stop after infra + kubeconfig (old two-step behavior).

```bash
# 1. Provision infra, wait for k3s, and bootstrap ArgoCD — one shot
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
export TF_VAR_tailscale_authkey="tskey-auth-..."
export TF_VAR_cloudflare_api_token="..."
export ARGOCD_ADMIN_PASSWORD="your-password"
bash scripts/deploy.sh

# 1b. Infra only, bootstrap ArgoCD yourself later
export SKIP_ARGOCD_BOOTSTRAP=true
bash scripts/deploy.sh
bash scripts/bootstrap-argocd.sh   # once per fresh cluster

# 2. Destroy when done (EIP is preserved)
export TAILSCALE_API_TOKEN="tskey-api-..."
bash scripts/destroy.sh

# 2b. Full teardown instead (EC2 + VPC + EIP allocation released, DNS records kept)
export TAILSCALE_API_TOKEN="tskey-api-..."
bash scripts/destroy-all.sh
```

## CI/CD workflow (GitHub Actions)

- **ci-fast.yml** — push to `dev`: gitleaks + terraform lint
- **ci-pr.yml** — PR to `main`: gitleaks + terraform lint + Checkov
- **deploy.yml** — manual `workflow_dispatch`: provisions VPC + EC2 + EIP + DNS, waits for
  k3s, then bootstraps ArgoCD + App of Apps in the same run (mirrors `deploy.sh` locally) —
  fully automated end-to-end, no manual follow-up step
- **destroy.yml** — manual `workflow_dispatch`: destroys EC2, preserves VPC + EIP + DNS
- **destroy-all.yml** — manual `workflow_dispatch`: destroys EC2 + VPC + EIP allocation, plus the
  `hello`/`kuberflow` DNS records (recreated on next deploy). `apex`/`www` are untouched — not managed
  by this repo at all (Cloudflare Pages custom domain)

## Validation commands

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
tflint --recursive
```

## Troubleshooting

- **`hello`/`kuberflow` intermittently resolve to the wrong place, or a domain you don't recognize**:
  Cloudflare allows multiple `A` records at the same hostname and round-robins between them — it does
  **not** warn you or replace an existing record when Terraform creates a new one at the same name.
  If a record was ever added manually (outside Terraform) before being adopted here, you can end up
  with a stale manual record *and* the Terraform-managed one both live at once. Check with
  `dig <name>.shengjunye.me +noall +answer` — if it lists more than one `A` record, delete the
  stale/non-Terraform one directly via the Cloudflare dashboard or API (list records with
  `GET /zones/<zone_id>/dns_records?name=<name>.shengjunye.me`, confirm the ID against the one
  Terraform created before deleting the other).
- **`hello`/`kuberflow` DNS resolves fine but connection is refused on 80/443**: `deploy.sh`/`deploy.yml`
  auto-bootstrap ArgoCD once k3s is `Ready`, but ArgoCD's own sync of `ingress-nginx` + the workload
  charts from `argocd-app-of-apps` still takes a few minutes after that. If you ran with
  `SKIP_ARGOCD_BOOTSTRAP=true`, nothing listens on 80/443 until you run `scripts/bootstrap-argocd.sh`
  yourself. Either way, not a bug — just means ingress/workloads haven't synced yet.

## Key invariants — do not break these

- **`aws_eip.k3s` must never be destroyed by `destroy.sh`/`destroy.yml`** — it is the target of the
  `hello`/`kuberflow` DNS records. `destroy-all.sh`/`destroy-all.yml` is the sole intentional
  exception: it releases the EIP (and VPC) for a full teardown, and removes those two DNS records
  along with it (they're recreated on the next deploy).
- **This repo does not manage `shengjunye.me` / `www` DNS at all** — that's a Cloudflare Pages custom
  domain (CNAME, owned by `website/.github/workflows/deploy-cloudflare.yml`, project `shengsite`).
  Do not add `cloudflare_dns_record.apex`/`.www` resources here: Cloudflare rejects an `A` record at
  a hostname that already has a CNAME (error 81054), and this would conflict with Pages' own DNS
  management of the live production site.
- **Cloudflare, not Porkbun, is authoritative for `shengjunye.me` DNS** — Porkbun remains only the
  domain registrar (NS delegation points at Cloudflare). Don't reintroduce a `porkbun` provider here.
- **No static AWS credentials** — OIDC only in CI; `aws configure` / SSO locally
- **`module.helm-argocd` does not exist** — ArgoCD is bootstrapped via `scripts/bootstrap-argocd.sh`,
  which is not Terraform; `deploy.sh`/`deploy.yml` auto-chain into it as a shell/CI step, not a
  Terraform resource
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
