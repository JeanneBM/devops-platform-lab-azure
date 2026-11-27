# Terraform plan verification — 27 November 2026

## Provenance and environment

This record summarizes terminal output supplied by the repository owner from a
Windows workstation. The output was reviewed on 27 November 2026. It is a local
authenticated Terraform planning exercise, separate from GitHub Actions and the
existing kind deployment evidence.

| Item | Observed value |
| --- | --- |
| Configuration commit | `8e363351b4abf3e3580d79bc255a40eba0084fc0` |
| Terraform | 1.9.8, windows_amd64 |
| Provider | registry.terraform.io/hashicorp/azurerm 4.45.1 |
| Azure CLI | 2.91.0 |
| PowerShell | 7.7.0, invoked from Git Bash |
| Azure context | Enabled subscription, interactive user authentication |
| Region | polandcentral |
| Planned Kubernetes version | 1.37.1, returned by the operator's regional version query |
| Pre-run local files | lab.tfvars and infra/terraform.tfstate absent |
| Post-init local modification | Reviewed addition of one h1 package checksum; AzureRM version/constraint unchanged |

The operator reported no other tracked working-tree modifications. The provider
version reported after initialization matches the repository constraint. The
supplied lock diff adds only this package-content checksum:

```text
h1:gzxUmsNMGsICKFTrJoEcXxAhJZmqAF2+sXpYmPUGXLc=
```

There is no provider version or constraint change. In the context of the
reported successful Windows initialization, this is the expected additional h1
checksum for the installed platform package. HashiCorp documents this behavior
in [New provider package checksums](https://developer.hashicorp.com/terraform/language/files/dependency-lock#new-provider-package-checksums).
This review used the supplied diff and init output; it did not independently
download and hash the Windows package. The LF/CRLF warning concerns Git's line
ending handling on Windows.

## Commands and observed results

The operator generated a Git-ignored `lab.tfvars` from the current Azure context,
operator object ID, public IPv4 /32 and a unique lab suffix, then invoked:

```bash
pwsh -NoProfile -File ./scripts/Start-Lab.ps1
```

No `-Apply` switch was used. The supplied output records:

| Operation | Result |
| --- | --- |
| terraform init | Successfully initialized |
| terraform validate | Configuration valid |
| data.azurerm_client_config.current | Read completed |
| terraform plan | 7 to add, 0 to change, 0 to destroy |
| Saved plan | infra/create.tfplan on the operator's workstation |
| Script completion | PLAN ONLY |

## Planned resources and dependencies

| Terraform address | Configuration / dependency |
| --- | --- |
| azurerm_resource_group.lab | Lab resource group in polandcentral |
| azurerm_container_registry.lab | Basic ACR in the lab group; administrator credentials disabled |
| azurerm_kubernetes_cluster.lab | AKS in the lab group; two Standard_D4as_v5 Linux nodes, 64 GiB managed OS disk per node |
| azurerm_role_assignment.pull | AcrPull at the ACR scope for the AKS kubelet identity |
| azurerm_role_assignment.operator | Azure Kubernetes Service RBAC Cluster Admin at the AKS scope for the human operator |
| azurerm_role_assignment.operator_credentials | Azure Kubernetes Service Cluster User Role at the AKS scope for the human operator |
| azurerm_role_assignment.operator_push | AcrPush at the ACR scope for the human operator |

The plan also records Azure CNI Overlay, Azure network policy, Entra/Azure RBAC,
disabled local AKS accounts, OIDC and Workload Identity support, and an API-server
allowlist containing only the operator's /32. Resource IDs, kubelet principal ID,
registry endpoint and OIDC issuer are expected to remain unknown until apply.

## Evidence boundaries

This initial exercise verifies initialization, provider-schema validation and generation of a
saved plan using the authenticated operator context. Apply, Azure resource
creation, effective role assignments, quota/capacity, application deployment and
destroy were outside that initial exercise. A later infrastructure-only session
on the same day verified resource creation, inspection and destruction; see the
[separate live record](2026-11-27-terraform-live.md). Application validation
remains L1 on kind.

The original transcript contains subscription/tenant/operator identifiers and a
public IP. Those values and the unique resource names are omitted here. The raw
binary plan, tfvars and Terraform state remain local and Git-ignored. No binary
plan checksum was supplied, so this record does not claim byte-level provenance
of that local file.

Preserve the reviewed local dependency-lock addition. Before a future apply, check
resource-provider registration, regional VM capacity/quota and resource/role
assignment permissions, then follow the existing cost and cleanup instructions.
