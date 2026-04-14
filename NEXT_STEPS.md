# Next Steps

## 1. Fill in `terraform.tfvars` — 3 placeholders remain

```hcl
tailscale_oauth_clientid = "YOUR_CLIENT_ID_HERE"    # placeholder
tailscale_oauth_secret   = "YOUR_CLIENT_SECRET_HERE" # placeholder
tailscale_authkey        = null                       # will break user_data
argocd_github_repo       = "https://github.com/TU_USER/argocd-apps" # placeholder
```

**Tailscale pre-auth key** (for EC2 node):
- Go to: https://login.tailscale.com/admin/settings/keys
- Generate auth key → set reusable + expiry
- Paste as `tailscale_authkey`

**Tailscale OAuth** (for in-cluster operator — optional):
- Go to: https://login.tailscale.com/admin/settings/oauth
- Create client → paste `client_id` and `client_secret`
- If not needed yet, set both to `null`

**ArgoCD repo**:
- Create `Illumidragui/argocd-apps` on GitHub (or point to an existing repo)
- Or set `argocd_github_repo = null` to skip the App of Apps release for now

---

## 2. Verify AWS credentials are active

```bash
aws sts get-caller-identity
```

If it fails: run `aws configure` or export `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.

---

## 3. Verify the S3 state bucket exists

```bash
aws s3 ls s3://devsecops-infra-tfstate
```

If it doesn't exist, create it:

```bash
aws s3api create-bucket --bucket devsecops-infra-tfstate --region us-east-1
aws s3api put-bucket-encryption --bucket devsecops-infra-tfstate \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

---

## 4. Phase 1 — Deploy VPC + EC2

In `main.tf`, set the `helm-argocd` module to `create = false`, then:

```bash
terraform init
terraform apply -var-file=terraform.tfvars
```

---

## 5. Copy the kubeconfig (once EC2 is up and Tailscale connected)

```bash
TAILSCALE_IP=<your-node-tailscale-ip>  # visible in Tailscale admin panel or terraform output

ssh ec2-user@$TAILSCALE_IP "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/$TAILSCALE_IP/g" > ~/.kube/devsecops-config
```

---

## 6. Phase 2 — Deploy ArgoCD

Set `create = true` on the `helm-argocd` module in `main.tf`, then:

```bash
terraform apply -var-file=terraform.tfvars
```
