# Stage 1 — Terraform foundation and local lifecycle

## Goal

Explain the boundary between infrastructure, node identity, operator permissions
and future workload identities. Prepare a plan, later create the resources under
explicit authorization, verify them, and destroy the same Terraform-managed lab.

## Prerequisites

Use PowerShell 7.2+, Azure CLI and Terraform 1.9.8+ (<2.0). CI uses Terraform 1.9.8
and AzureRM 4.45.1. Install kubectl and Azure kubelogin before live verification.
Azure CLI authentication must belong to the tenant containing the subscription.
The deploying account needs resource creation and role-assignment rights in the
target subscription (for example Contributor plus Role Based Access Control Administrator).
The named operator must belong to that tenant. Do not grant Owner to workload pods.

The provider does not auto-register resource providers. Check their registration
first. Registration is an explicit subscription mutation, not part of plan mode.

```powershell
az login
$subscription = '<target subscription UUID>'
az account show --subscription $subscription --query '{id:id,tenant:tenantId,name:name}'
az ad signed-in-user show --query id -o tsv
foreach ($provider in @('Microsoft.ContainerService','Microsoft.ContainerRegistry','Microsoft.Compute','Microsoft.Network','Microsoft.ManagedIdentity','Microsoft.Storage')) {
    az provider show --subscription $subscription --namespace $provider --query '{namespace:namespace,state:registrationState}'
}
az aks get-versions --subscription $subscription --location polandcentral -o table
az vm list-usage --subscription $subscription --location polandcentral -o table
az vm list-skus --subscription $subscription --location polandcentral --size Standard_D4as_v5 --all -o table
```

If a provider is unregistered, an authorized subscription administrator must register
it before apply. Check that the selected SKU is not restricted for this subscription.
The pool requests 8 regional/family vCPUs; keep headroom for upgrade surge capacity.
Two nodes are an intentional conservative starting point; do not substitute a B-series
system pool to lower the bill. Check current AKS restrictions before resizing.

Copy `lab.tfvars.example` to `lab.tfvars`. Set the explicit subscription, Entra user
object ID, unique suffix, supported Kubernetes version and your current public IPv4
as `/32`. Get your egress IP from your network/router or an approved IP-check service.
The example documentation address is rejected. Do not use `0.0.0.0/0`.
If your public IP changes, update the CIDR and re-plan; do not disable the allowlist.

## Exercise A — no resources created

```powershell
Copy-Item lab.tfvars.example lab.tfvars
# Edit lab.tfvars now, then:
pwsh ./scripts/Start-Lab.ps1
```

Inspect the plan: one AKS cluster, one ACR, one lab resource group and two scoped role
assignments. AKS also creates its managed node resource group and billable network,
compute and disk resources. No Log Analytics workspace or application resources
should appear. Terraform refresh/read calls are real Azure reads, not a simulated plan.

The generated `infra/create.tfplan` contains sensitive configuration/state information;
never commit or upload it publicly. The committed `infra/.terraform.lock.hcl` pins provider checksums; retain it for deployment. State and plan
stay on the same workstation; this stage does not implement team/remote state.

## Exercise B — only after authorization to incur costs

```powershell
pwsh ./scripts/Start-Lab.ps1 -Apply
$subscription = '<same subscription UUID>'
$rg = terraform -chdir=infra output -raw resource_group_name
$cluster = terraform -chdir=infra output -raw cluster_name
$acr = terraform -chdir=infra output -raw acr_name
az aks show --subscription $subscription -g $rg -n $cluster --query '{state:provisioningState,sku:sku,oidc:oidcIssuerProfile.enabled,workloadIdentity:securityProfile.workloadIdentity.enabled,localAccountsDisabled:disableLocalAccounts}'
az acr show --subscription $subscription -g $rg -n $acr --query '{sku:sku.name,adminEnabled:adminUserEnabled}'
New-Item -ItemType Directory -Force .local | Out-Null
$env:KUBECONFIG = Join-Path (Get-Location) '.local/aks.kubeconfig'
az aks get-credentials --subscription $subscription -g $rg -n $cluster --file $env:KUBECONFIG --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes -o wide
kubectl get pods -A
kubectl auth can-i create namespaces
```

Expected: provisioning succeeded, two ready nodes, system pods healthy, OIDC/WI true,
local accounts disabled, Basic ACR with admin disabled. The named operator can create
namespaces. Azure role propagation may take several minutes. Do not use `--admin`.
This is operator authorization only: namespace-scoped workload permissions and negative
RBAC tests belong to stage 3. No applications exist in stage 1.

## Exercise C — cleanup and proof

Keep an encrypted/private copy of `infra/terraform.tfstate` and `.backup` while resources
exist. The state may contain secrets even though no kubeconfig output is declared.
Do not delete state, rename the prefix, or change subscriptions to clean up an old lab.
Use the original state/config. If state is lost, restore it or import existing resources
before using Terraform; an empty plan is not proof that Azure is empty.

```powershell
$subscription = '<same subscription UUID>'
$rg = terraform -chdir=infra output -raw resource_group_name
$nodeRg = terraform -chdir=infra output -raw node_resource_group_name
pwsh ./scripts/Stop-Lab.ps1
# Review deletion plan. In future stages, back up Jenkins outside Azure first.
pwsh ./scripts/Stop-Lab.ps1 -Destroy
az group exists --subscription $subscription --name $rg
az group exists --subscription $subscription --name $nodeRg
terraform -chdir=infra state list
```

Expected: both `az group exists` calls return `false`, and state list is empty. If either
group remains, investigate; do not assume billing has stopped. Cost reporting can lag.
If apply fails part-way, retain state and use Stop-Lab with the original config.
Re-cloning the repo does not restore state or remove existing resources.

## Explain it in an interview

* Terraform owns Azure resources; Helm will own Kubernetes releases.
* Entra authenticates the human; Azure RBAC for Kubernetes authorizes the operator.
* Kubelet identity pulls images with registry-scoped AcrPull, without ACR admin keys.
* OIDC/WI prepares a way for specific pods to request Azure tokens. Federated credentials
  and Azure role scopes are still required; they will be added only for real consumers.
* A budget alert is not a spending stop. Destroy, verification and short sessions control costs.
* A successful schema check does not prove a successful deployment. Record live evidence separately.

## Verification record

At preparation time: no Azure apply, no real role test, no live destruction test.
CI validates formatting, provider schema and PowerShell parsing without Azure credentials.
After a future authorized session, record date, commit, region, redacted verification
results, runtime and cleanup results. Keep subscription IDs, tokens and kubeconfigs private.
