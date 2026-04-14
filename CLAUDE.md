# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Terraform-based DevSecOps infrastructure project that provisions:
- An AWS VPC with public/private subnets and NAT Gateway
- An EC2 instance running k3s (lightweight Kubernetes) in the private subnet
- Tailscale VPN for secure access (no public IP on EC2)
- ArgoCD deployed via Helm using the App of Apps pattern

## Common Commands

```bash
# Initialize (downloads providers and modules)
terraform init

# Preview changes
terraform plan -var-file=terraform.tfvars

# Apply changes
terraform apply -var-file=terraform.tfvars

# Destroy infrastructure
terraform destroy -var-file=terraform.tfvars

# Validate configuration
terraform validate

# Format code
terraform fmt -recursive

# Target a specific module
terraform plan -target=module.vpc
terraform apply -target=module.ec2
```

## Required Variables (terraform.tfvars — gitignored)

```hcl
ssh_public_key      = "ssh-rsa ..."
tailscale_authkey   = "tskey-auth-..."
argocd_github_repo  = "https://github.com/YOUR_USER/argocd-apps"

# Optional overrides
aws_region    = "us-east-1"
environment   = "dev"      # dev | staging | prod
instance_type = "t2.micro"
```

## Architecture

```
root/
├── main.tf          # Provider config + module wiring
├── variables.tf     # Root-level variable declarations
├── locals.tf        # Common tags, port constants
├── outputs.tf       # Exposes instance_ip
├── backend.tf       # S3 remote state (bucket: devsecops-infra-tfstate)
└── tf-modules/
    ├── aws-vpc/     # VPC, public/private subnets, NAT Gateway, route tables
    ├── aws-ec2/     # EC2 k3s node, security group, key pair, Elastic IP
    └── helm-argocd/ # ArgoCD + App of Apps via Helm
        └── helm-values/
            ├── argo-cd.yaml     # ArgoCD Helm values (resource limits, server config)
            └── app-of-apps.yaml # ArgoCD Application CR pointing to GitOps repo
```

### Network Design
- EC2 lives in the **private subnet** (`10.0.1.0/24`) with no public IP
- Outbound internet access via NAT Gateway in the **public subnet** (`10.0.0.0/24`)
- Access to EC2 is exclusively through **Tailscale VPN** (installed via user_data)
- k3s TLS SAN is set to the Tailscale IP, not a public IP

### Deployment Flow
1. `module.vpc` creates networking (VPC, subnets, NAT, route tables)
2. `module.ec2` depends on VPC; provisions EC2, installs Tailscale, then k3s
3. `module.helm-argocd` depends on EC2; deploys ArgoCD and App of Apps chart via Helm provider (kubeconfig: `~/.kube/devsecops-config`)

### ArgoCD Access
- Helm provider connects via kubeconfig at `~/.kube/devsecops-config`
- ArgoCD service type is `LoadBalancer` (creates NLB in AWS)
- Current values.yaml uses `--insecure` flag and a hashed default password — dev only
- The App of Apps pattern means ArgoCD manages all other app deployments from the `argocd_github_repo`

## State Backend

Remote state stored in S3: `devsecops-infra-tfstate/k8s-cluster/terraform.tfstate` (us-east-1, encrypted). Requires AWS credentials with access to that bucket before running `terraform init`.

## Known Gaps / TODOs

- `tf-modules/helm-argocd/variables.tf` declares `instance_ip`, `my_ip`, `ssh_public_key`, `instance_type` that are not all wired in `main.tf` — the module interface is in flux
- `argocd_github_repo` default is `https://github.com/TODO/argocd-apps` — must be set in tfvars
- `tf-modules/helm-argocd/helm-values/argo-cd.yaml` is referenced in `helm-argocd/main.tf` but not yet present in the repo (only `values.yaml` exists at the module root)
