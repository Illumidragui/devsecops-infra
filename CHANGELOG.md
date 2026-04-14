# Changelog

## Refactor: Align structure with OCI reference repo (`ricardllop/tf-oci-cluster-infra`)

The goal of this refactor was to adopt the same modular patterns used in the OCI reference repo,
adapted for AWS and personal tokens. All modules are now self-contained, support a `create` toggle
for staged deployments, and the Helm/Kubernetes providers live inside the `helm-argocd` module.

---

### `locals.tf` (root)

**Change:** Removed `timestamp()` from `common_tags`.

**Why:** `timestamp()` is re-evaluated on every `terraform plan`, causing Terraform to perpetually
detect a tag drift and want to update every tagged resource. Removing it makes plans stable.

---

### `main.tf` (root)

**Changes:**
- Added `kubernetes` to `required_providers` (needed now that the Kubernetes provider is used in `helm-argocd`).
- Added `create = true` flag to all module calls — mirrors the OCI repo's staged deployment pattern.
- Added `kubeconfig_path`, `tailscale_oauth_clientid`, and `tailscale_oauth_secret` arguments to the `helm-argocd` module call.
- Removed `instance_ip` from the `helm-argocd` module call — it was passed in but never used.
- Removed `depends_on = [module.ec2]` from `helm-argocd` — Terraform does not allow `depends_on` on modules that define their own providers. Deployment order is now controlled by the `create` flag instead.
- Moved hardcoded strings into a `locals` block for consistency.

**Why:** The `create` flag replaces `depends_on` as the sequencing mechanism, matching the OCI
pattern where you set `create = false` on downstream modules, apply, then flip to `true` once
prerequisites are ready.

---

### `variables.tf` (root)

**Changes:**
- Clarified descriptions across all variables.
- Split Tailscale credentials into two distinct variables:
  - `tailscale_authkey` — pre-auth key used by the EC2 node's `user_data` script to join the network.
  - `tailscale_oauth_clientid` / `tailscale_oauth_secret` — OAuth credentials for the in-cluster Tailscale operator (deployed via Helm).
- Added `kubeconfig_path` variable (default: `~/.kube/devsecops-config`) to make the kubeconfig location configurable instead of hardcoded.
- Fixed `argocd_github_repo` default to point to the actual user repo (`Illumidragui/argocd-apps`).

**Why:** Separating auth key from OAuth credentials matches how Tailscale itself distinguishes
between node-level auth (pre-auth keys) and operator-level auth (OAuth). It also makes both
optional independently.

---

### `outputs.tf` (root)

**Change:** Added `tailscale_hostname` output.

**Why:** Useful to know the Tailscale hostname after `terraform apply` so you can SSH in and copy
the kubeconfig.

---

### `tf-modules/aws-vpc/variables.tf`

**Change:** Added `create` boolean variable (default `true`).

**Why:** Allows the VPC module to be toggled off without removing it from `main.tf`, consistent
with the OCI repo's per-module `create` pattern.

---

### `tf-modules/aws-vpc/main.tf`

**Change:** Added `count = var.create ? 1 : 0` to every resource. Updated all internal
cross-references to use `[0]` indexing (e.g. `aws_vpc.main[0].id`).

**Why:** Required to implement the `create` toggle. When `create = false`, no resources are
created and outputs return `null`.

---

### `tf-modules/aws-vpc/outputs.tf`

**Changes:**
- All outputs are now conditional: `var.create ? <resource>[0].<attr> : null`.
- Added the missing `public_subnet_id` output.

**Why:** `public_subnet_id` was missing despite being referenced in the root `main.tf` comment
and needed by the NAT Gateway. Conditional outputs prevent errors when `create = false`.

---

### `tf-modules/aws-ec2/variables.tf`

**Changes:**
- Added `create` boolean variable (default `true`).
- Renamed `tailscale_auth_key` → `tailscale_authkey` to match the root variable name.
- Improved descriptions.

**Why:** Consistency with root variable naming and the `create` pattern.

---

### `tf-modules/aws-ec2/main.tf`

**Changes:**
- Added the **missing resources** that were referenced in the file but never defined:
  - `data "aws_ami" "amazon_linux"` — fetches the latest Amazon Linux 2023 AMI dynamically.
  - `aws_key_pair "main"` — registers the SSH public key in AWS.
  - `aws_security_group "k3s"` — allows intra-VPC traffic and all outbound; no public inbound.
- Added `count = var.create ? 1 : 0` to `aws_instance`, `aws_key_pair`, and `aws_security_group`.
- Fixed `user_data`: added `systemctl enable --now tailscaled` before `tailscale up` so the
  daemon is guaranteed to be running, and stored the Tailscale IP in a variable before passing
  it to the k3s TLS SAN.

**Why:** The module would have errored on `terraform plan` because `data.aws_ami.amazon_linux`,
`aws_key_pair.main`, and `aws_security_group.k3s` were referenced but not defined anywhere.

---

### `tf-modules/aws-ec2/outputs.tf`

**Change:** All outputs are now conditional on `var.create`.

**Why:** Prevents null-reference errors when the module is toggled off.

---

### `tf-modules/helm-argocd/variables.tf`

**Changes:**
- Added `create` boolean variable (default `true`).
- Added `kubeconfig_path` — path to the k3s kubeconfig file.
- Added `namespace` — Kubernetes namespace for ArgoCD (default `argo-cd`), threaded into `templatefile` calls.
- Added `tailscale_oauth_clientid` and `tailscale_oauth_secret` for the in-cluster operator.
- Removed `instance_ip` — it was declared and passed in but never used inside the module.

**Why:** The module is now fully self-contained: it owns its provider configuration and receives
all the credentials it needs as variables, exactly like the OCI `helm-argocd` module.

---

### `tf-modules/helm-argocd/main.tf`

**Changes:**
- **Moved `kubernetes` and `helm` providers inside the module** (previously defined in root `main.tf`). Both use `var.kubeconfig_path`.
- **Added Tailscale operator namespace + OAuth secret** (mirrored from OCI repo):
  - `kubernetes_namespace_v1 "tailscale"` — creates the `tailscale-operator` namespace.
  - `kubernetes_secret_v1 "tailscale_operator_oauth"` — stores OAuth credentials as a Kubernetes secret.
  - Both are only created when OAuth credentials are provided (`!= null`).
- Added `count = var.create ? 1 : 0` to all helm releases and Tailscale resources.
- Renamed helm release `argocd` → `argo-cd` and `app_of_apps` → `argocd-apps` to match OCI conventions.
- Updated `argo-cd` chart to use `templatefile` with `namespace` variable.
- Fixed `argocd-apps` release: added missing `repository` field (was absent, would have errored).

**Why:** Self-contained modules are easier to reason about and test independently. The Tailscale
operator pattern (namespace + OAuth secret) is more robust than injecting a pre-auth key via
`user_data` — the operator handles key rotation automatically.

---

### `tf-modules/helm-argocd/outputs.tf`

**Change:** Output is now conditional on `var.create`. References `helm_release.argo-cd[0]`
to match the new `count`-based resource.

**Why:** Prevents errors when `create = false`.

---

### `tf-modules/helm-argocd/helm-values/argo-cd_values.yaml`

**Change:** Completely replaced. The previous file contained a raw Kubernetes `Application`
Custom Resource manifest, which is not valid as Helm chart values.

**Why:** When passed to `helm install` as a values file, Helm tries to interpret the content as
`key: value` overrides for the chart's `values.yaml`. A raw CRD manifest would either be silently
ignored or cause a parse error. The new file contains valid ArgoCD Helm chart overrides:
resource limits, `--insecure` flag for dev, hashed admin password, and the Tailscale expose
annotation (`tailscale.com/expose: "true"`) so the ArgoCD UI is reachable over the VPN.

---

### `tf-modules/helm-argocd/helm-values/app-of-apps.yaml`

**Change:** Replaced hardcoded `repoURL` with `${argocd_github_repo}` template placeholder.
Replaced hardcoded namespace with `${namespace}`. Reformatted to match the `argocd-apps` chart
schema used in the OCI repo.

**Why:** The previous file had a hardcoded GitHub URL (`TU_USER/argocd-apps`) and was structured
as a raw Kubernetes manifest rather than values for the `argocd-apps` Helm chart. It is now
injected via `templatefile()` in `main.tf`, making the repo URL and namespace fully configurable.

---

### Deleted files

| File | Reason |
|---|---|
| `tf-modules/helm-argocd/values.yaml` | Duplicate/stale — superseded by `helm-values/argo-cd_values.yaml`. |
| `PROPOSED_CHANGES.md` | All proposed changes have been applied. |

---

### Two-phase deployment workflow

Because the `helm-argocd` module's Helm provider needs a kubeconfig that only exists after k3s
is running, deployment must be done in two phases (same pattern as the OCI repo's `create` flag):

```bash
# Phase 1 — provision VPC + EC2
# In main.tf, set helm-argocd create = false, then:
terraform apply -var-file=terraform.tfvars

# Copy kubeconfig once k3s is up (replace <tailscale-ip> with output from above):
ssh ec2-user@<tailscale-ip> "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/<tailscale-ip>/g" > ~/.kube/devsecops-config

# Phase 2 — deploy ArgoCD
# In main.tf, set helm-argocd create = true, then:
terraform apply -var-file=terraform.tfvars
```
