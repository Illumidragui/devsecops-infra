# devsecops-infra

Terraform infrastructure for a private Kubernetes lab on AWS. Deploys a single-node k3s cluster accessible exclusively through a Tailscale VPN — no public SSH or API ports exposed.

## Architecture

```
GitHub Actions
     │
     │ OIDC (no static credentials)
     ▼
AWS IAM Role
     │
     ├── VPC (10.0.0.0/16)
     │    ├── Public subnet  (10.0.0.0/24) ── NAT Gateway ── Internet
     │    └── Private subnet (10.0.1.0/24)
     │
     ├── EC2 t3.medium (Amazon Linux 2023)
     │    ├── k3s (single-node Kubernetes)
     │    ├── Tailscale (WireGuard VPN)
     │    └── ingress-nginx
     │
     └── Elastic IP (static, survives redeploys)

ArgoCD (App of Apps) ── GitHub repo (argocd-app-of-apps)
```

Access to the cluster (SSH, kubectl) is only possible through Tailscale. The security group exposes only ports 80, 443, and UDP 41641 (Tailscale WireGuard) to the internet.

## Prerequisites

| Tool | Purpose |
|------|---------|
| Terraform >= 1.0 | Infrastructure provisioning |
| AWS account | Cloud provider |
| Tailscale account | VPN access |
| S3 bucket `devsecops-infra-tfstate` | Terraform state backend |

## Repository structure

```
├── main.tf                        # Root module — wires VPC, EC2, EIP, ArgoCD
├── variables.tf                   # Input variables
├── outputs.tf                     # Public IP, Tailscale hostname
├── backend.tf                     # S3 remote state
├── tf-modules/
│   ├── aws-vpc/                   # VPC, subnets, IGW, NAT Gateway, route tables
│   ├── aws-ec2/                   # EC2 instance, security group, SSH key pair
│   └── helm-argocd/               # ArgoCD, ingress-nginx, App of Apps, Tailscale operator
└── .github/workflows/
    ├── deploy.yml                 # Two-phase deploy (VPC+EC2 → ArgoCD)
    └── destroy.yml                # Ordered teardown (ArgoCD → EC2, EIP preserved)
```

## GitHub secrets and variables

### Secrets (`secrets.*`)

| Name | Description |
|------|-------------|
| `SSH_PUBLIC_KEY` | Public key installed on the EC2 instance |
| `SSH_PRIVATE_KEY` | Matching private key used by the runner to SSH in — **no passphrase** |
| `TAILSCALE_AUTHKEY` | Pre-auth key to register the EC2 into the Tailnet (reusable, non-ephemeral) |
| `TAILSCALE_OAUTH_CLIENTID` | OAuth client ID for the Tailscale GitHub Action and in-cluster operator |
| `TAILSCALE_OAUTH_SECRET` | OAuth client secret (matching above) |
| `TAILSCALE_API_TOKEN` | API access token (`tskey-api-...`) used to remove the device on destroy |

### Variables (`vars.*`)

| Name | Description |
|------|-------------|
| `AWS_ROLE_ARN` | IAM role ARN assumed via OIDC — not sensitive, stored as a variable |

### Generating the SSH key pair

```bash
ssh-keygen -t ed25519 -C "devsecops-deploy" -f ~/.ssh/devsecops_deploy -N ""
# SSH_PUBLIC_KEY  → contents of ~/.ssh/devsecops_deploy.pub
# SSH_PRIVATE_KEY → contents of ~/.ssh/devsecops_deploy
```

### Setting secrets and variables

```bash
gh secret set SSH_PUBLIC_KEY       --repo Illumidragui/devsecops-infra < ~/.ssh/devsecops_deploy.pub
gh secret set SSH_PRIVATE_KEY      --repo Illumidragui/devsecops-infra < ~/.ssh/devsecops_deploy
gh secret set TAILSCALE_AUTHKEY    --repo Illumidragui/devsecops-infra
gh secret set TAILSCALE_OAUTH_CLIENTID --repo Illumidragui/devsecops-infra
gh secret set TAILSCALE_OAUTH_SECRET   --repo Illumidragui/devsecops-infra
gh secret set TAILSCALE_API_TOKEN  --repo Illumidragui/devsecops-infra
gh variable set AWS_ROLE_ARN       --repo Illumidragui/devsecops-infra
```

## Tailscale ACL requirements

The Tailscale ACL policy must allow the following:

```json
{
  "tagOwners": {
    "tag:ci":         ["autogroup:admin"],
    "tag:k3s":        ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src":    ["tag:ci"],
      "dst":    ["tag:k3s:*"]
    }
  ]
}
```

- `tag:ci` — assigned to the GitHub Actions runner via the OAuth client
- `tag:k3s` — assigned to the EC2 instance via the pre-auth key

## Deploy

Trigger the **Deploy Infrastructure** workflow from GitHub Actions (`workflow_dispatch`) and type `deploy` to confirm.

**What happens:**
1. Runner joins the Tailnet and waits for the `lab-kubernetes` hostname slot to be free (handles rapid destroy → redeploy cycles)
2. Phase 1: VPC, EC2, and Elastic IP are created. The EC2 user data installs Tailscale and k3s automatically.
3. Runner polls until k3s is ready, then copies the kubeconfig over SSH.
4. Phase 2: ArgoCD, ingress-nginx, and the App of Apps chart are deployed via Helm.

The Elastic IP is created outside the EC2 module so it survives destroy/redeploy cycles — your DNS record never changes.

## Destroy

Trigger the **Destroy Infrastructure** workflow and type `destroy` to confirm.

**What happens:**
1. Removes the EC2 from Tailscale via the API (instant — no waiting for ephemeral cleanup)
2. If the cluster is reachable: tears down ArgoCD Helm releases cleanly
3. If the cluster is already gone: removes the Helm state from Terraform so the next deploy starts clean
4. Destroys the EC2 and EIP association — **the Elastic IP allocation is preserved**

## Local development

```bash
# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars   # or create terraform.tfvars manually

# Required variables (no defaults):
# ssh_public_key    = "ssh-ed25519 AAAA..."
# tailscale_authkey = "tskey-auth-..."

terraform init
terraform plan
terraform apply
```

After the EC2 is up, copy the kubeconfig:

```bash
TAILSCALE_IP=$(tailscale ip -4 lab-kubernetes)
scp -i ~/.ssh/devsecops_deploy ec2-user@${TAILSCALE_IP}:/etc/rancher/k3s/k3s.yaml ~/.kube/devsecops-config
sed -i "s/127.0.0.1/${TAILSCALE_IP}/g" ~/.kube/devsecops-config
export KUBECONFIG=~/.kube/devsecops-config
kubectl get nodes
```
