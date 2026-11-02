# DevOps Platform Lab — Azure

An ephemeral Azure learning lab operated from a local PowerShell terminal.
Its counterpart is [devops-platform-lab-local](https://github.com/JeanneBM/devops-platform-lab-local).

**Status: Stage 1 — infrastructure preparation. No Azure deployment has been run.**
CI checks Terraform formatting/schema and PowerShell syntax. They do not prove Azure
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

Stage 1 creates infrastructure only. It does not deploy the applications or Jenkins.
Their future installation will extend this entrypoint rather than introduce a second
independent infrastructure deployment path.

Review a destruction plan, then explicitly destroy when ready:

```powershell
pwsh ./scripts/Stop-Lab.ps1
pwsh ./scripts/Stop-Lab.ps1 -Destroy
```

## Planned complete lab

| Stage | Deliverable and exercise | Status |
| --- | --- | --- |
| 1 | Terraform AKS/ACR, local lifecycle scripts; inspect identities and RBAC | Code prepared; live verification pending |
| 2 | Reuse Python/Java source and Dockerfiles; Helm releases, ACR build/push; health and rollback exercise | Planned |
| 3 | Jenkins Helm/JCasC, pinned plugins, shared library, dynamic Kubernetes agents; namespace-scoped RBAC and denied-operation exercise | Planned |
| 4 | Consistent Jenkins backup outside AKS, restore to a fresh PVC; prove jobs/configuration survive | Planned |
| 5 | Prometheus, Grafana, Loki and log collection; bounded retention, dashboards/alerts; broken-image, readiness and resource-pressure exercises | Planned |
| 6 | Budget/alerts, Cost Management review, cost report and complete one-command verification | Planned |

See [source review and reuse decisions](docs/source-review.md). The existing local
repository is preserved. Do not describe planned stages as implemented capabilities.
