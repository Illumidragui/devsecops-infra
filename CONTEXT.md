# Project Context — devsecops-infra

Use this file to onboard a new Claude session with full project context.

---

## What this repo is

A Terraform project that provisions a personal DevSecOps homelab on AWS:
- **VPC** with public/private subnets and NAT Gateway
- **EC2** running k3s (lightweight Kubernetes) in the private subnet
- **Tailscale VPN** for all access — EC2 has no public IP
- **ArgoCD** deployed via Helm using the App of Apps pattern

The structure was aligned with `ricardllop/tf-oci-cluster-infra` as a reference
(same project but on OCI), adapted for AWS.

---

## Repo structure

```
root/
├── main.tf          # Provider config + module wiring
├── variables.tf     # Root-level variable declarations
├── locals.tf        # Common tags, port constants
├── outputs.tf       # instance_ip, tailscale_hostname
├── backend.tf       # S3 remote state (bucket: devsecops-infra-tfstate, us-east-1)
├── terraform.tfvars # Personal tokens — gitignored
├── CHANGELOG.md     # Full record of all changes made and why
├── NEXT_STEPS.md    # Deployment checklist
└── tf-modules/
    ├── aws-vpc/     # VPC, subnets, NAT Gateway, route tables
    ├── aws-ec2/     # EC2 k3s node, security group, key pair, AMI lookup
    └── helm-argocd/ # ArgoCD + App of Apps via Helm
        └── helm-values/
            ├── argo-cd_values.yaml   # ArgoCD Helm values (resource limits, Tailscale annotation)
            └── app-of-apps.yaml      # ArgoCD Application CR pointing to GitOps repo
```

---

## Key design decisions

- **`create` flag per module** — each module accepts a `create = bool` variable.
  Set to `false` to skip resource creation without removing the module from `main.tf`.
  This is the sequencing mechanism for the two-phase deployment (VPC+EC2 first, ArgoCD second).

- **Helm/Kubernetes providers live inside `helm-argocd`** — the module is self-contained.
  Both providers use `var.kubeconfig_path` (default: `~/.kube/devsecops-config`).
  Because of this, `depends_on` cannot be used on that module — ordering is done via `create`.

- **Tailscale split**:
  - `tailscale_authkey` → pre-auth key injected into EC2 `user_data` for node-level VPN access.
  - `tailscale_oauth_clientid` / `tailscale_oauth_secret` → OAuth credentials for the
    in-cluster Tailscale operator (creates a Kubernetes secret in `tailscale-operator` namespace).
  - Tailscale annotation on ArgoCD service: `tailscale.com/expose: "true"` — makes the UI
    reachable over the VPN without a public LoadBalancer.

- **AMI** — fetched dynamically via `data "aws_ami"` (Amazon Linux 2023, x86_64).
  No hardcoded AMI IDs.

---

## Current state (as of last session)

- `terraform validate` passes.
- `terraform.tfvars` exists but has placeholder values that must be filled before deploying:
  - `tailscale_authkey` — set to `null`, needs a real pre-auth key.
  - `tailscale_oauth_clientid` / `tailscale_oauth_secret` — placeholder strings.
  - `argocd_github_repo` — placeholder URL.
- S3 state bucket (`devsecops-infra-tfstate`) may not exist yet — must be created manually.
- No infrastructure has been deployed yet.

---

## Two-phase deployment

```bash
# Phase 1 — VPC + EC2 (set helm-argocd create = false in main.tf)
terraform init
terraform apply -var-file=terraform.tfvars

# Copy kubeconfig once k3s is up:
ssh ec2-user@<tailscale-ip> "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/<tailscale-ip>/g" > ~/.kube/devsecops-config

# Phase 2 — ArgoCD (set helm-argocd create = true in main.tf)
terraform apply -var-file=terraform.tfvars
```

---

## Common commands

```bash
terraform init
terraform validate
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
terraform apply -target=module.vpc -var-file=terraform.tfvars
terraform destroy -var-file=terraform.tfvars
terraform fmt -recursive
```

---

## Variables reference (`terraform.tfvars`)

| Variable | Description | Where to get it |
|---|---|---|
| `aws_region` | AWS region | Pick one (default: `us-east-1`) |
| `project_name` | Resource name prefix | Anything (default: `devsecops`) |
| `environment` | `dev` / `staging` / `prod` | Your choice |
| `instance_type` | EC2 size | `t2.micro` for free tier |
| `ssh_public_key` | SSH public key for EC2 | `cat ~/.ssh/id_ed25519.pub` |
| `tailscale_authkey` | Tailscale pre-auth key | https://login.tailscale.com/admin/settings/keys |
| `tailscale_oauth_clientid` | Tailscale OAuth client ID | https://login.tailscale.com/admin/settings/oauth |
| `tailscale_oauth_secret` | Tailscale OAuth secret | Same as above |
| `argocd_github_repo` | GitOps repo URL | Your `argocd-apps` GitHub repo |
| `kubeconfig_path` | Path to k3s kubeconfig | Default: `~/.kube/devsecops-config` |

---

## Related repos

- **Reference (OCI version):** `ricardllop/tf-oci-cluster-infra` — same architecture on Oracle Cloud
- **GitOps repo (to be created):** `Illumidragui/argocd-apps` — App of Apps definitions
