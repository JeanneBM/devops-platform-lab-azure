# DevOps Platform Lab — Azure

An ephemeral Azure learning lab operated from a local PowerShell terminal.
Its counterpart is [devops-platform-lab-local](https://github.com/JeanneBM/devops-platform-lab-local).

**Status: Stage 2 — application/Helm code prepared. No Azure deployment has been run.**
CI checks Terraform, PowerShell and applications/Helm in a disposable kind cluster. These checks do not prove Azure
quota, regional capacity, authentication, billing, resource creation or destruction.

## Stage 1: what this code prepares

| Component | Configuration |
| --- | --- |
| AKS | Free management tier; two Linux `Standard_D4as_v5` nodes, 4 vCPU / 16 GiB each |
| Network | Azure CNI Overlay, Azure network-policy support, Standard outbound load balancer |
| Access | Public API limited to your public IPv4 /32; Entra authentication; local accounts disabled |
| Authorization | Named human operator: AKS RBAC Cluster Admin at this cluster only |
| ACR | Basic, admin credentials disabled; kubelet identity receives `AcrPull` at registry scope |
| Workload Identity | OIDC issuer and cluster support enabled; no workload identities/roles created yet |
| Storage | Managed node OS disks; no application PVCs until the Helm stage |
| Monitoring | No Log Analytics, Managed Prometheus or Managed Grafana provisioned |
| Terraform state | Local and untracked; preserve it until successful destroy |

This is a disposable learning topology. It mixes future workloads and system pods
on the same pool; it is not a production baseline or high-availability claim.
No public application endpoints are created. ACR has a public endpoint protected
by Entra authentication. The AKS egress load balancer/public IP still costs money.

## Start here

1. Read [the configuration, exercise and verification](docs/stage-01.md).
2. Read [cost assumptions and cleanup](docs/costs.md).
3. Copy `lab.tfvars.example` to `lab.tfvars` and replace every placeholder.
4. Sign in with Azure CLI, then prepare a plan:

```powershell
pwsh ./scripts/Start-Lab.ps1
```

The default command **does not apply the plan**. No CI job has Azure credentials.
After explicit approval to create paid resources, the future operator command is:

```powershell
pwsh ./scripts/Start-Lab.ps1 -Apply
```

With `-Apply`, Start-Lab creates infrastructure, builds both application images locally,
pushes them to ACR, deploys Helm releases and verifies HTTP behavior. It does not install
Jenkins yet. Required tools: Azure CLI, Terraform, Docker (Linux containers), PowerShell
7.2+, kubectl, kubelogin and **Helm 3**. See [stage 2](docs/stage-02.md).

Review a destruction plan, then explicitly destroy when ready:

```powershell
pwsh ./scripts/Stop-Lab.ps1
pwsh ./scripts/Stop-Lab.ps1 -Destroy
```

## Planned complete lab

| Stage | Deliverable and exercise | Status |
| --- | --- | --- |
| 1 | Terraform AKS/ACR, local lifecycle scripts; inspect identities and RBAC | Code prepared; live verification pending |
| 2 | Reused Python/Java source; multistage images; Helm releases, ACR push; health and rollback exercise | Code prepared; Azure verification pending |
| 3 | Jenkins Helm/JCasC, pinned plugins, shared library, dynamic Kubernetes agents; namespace-scoped RBAC and denied-operation exercise | Planned |
| 4 | Consistent Jenkins backup outside AKS, restore to a fresh PVC; prove jobs/configuration survive | Planned |
| 5 | Prometheus, Grafana, Loki and log collection; bounded retention, dashboards/alerts; broken-image, readiness and resource-pressure exercises | Planned |
| 6 | Budget/alerts, Cost Management review, cost report and complete one-command verification | Planned |

See [source review and reuse decisions](docs/source-review.md). The existing local
repository is preserved. Do not describe planned stages as implemented capabilities.
