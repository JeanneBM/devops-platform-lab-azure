# DevOps Platform Lab — Azure

An ephemeral Azure learning lab operated from a local PowerShell terminal.
Its counterpart is [devops-platform-lab-local](https://github.com/JeanneBM/devops-platform-lab-local).

**Status: Stages 1–6 implemented in code. No Azure deployment has been run.**
CI checks Terraform/PowerShell, Helm applications, Jenkins dynamic builds and recovery,
plus metrics/logs/dashboards and outage alert recovery in kind. These checks do not prove Azure
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
| Storage | Managed node OS disks plus a 10 GiB Jenkins PVC (managed-csi) |
| Monitoring | Self-hosted Prometheus/Grafana/Loki/Alloy, HTTP probes and Kubernetes state; no paid managed monitoring |
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
pushes them to ACR, deploys Helm releases and verifies HTTP behavior. It also installs Jenkins, runs a shared-library verification pipeline on a dynamic
Kubernetes agent and verifies RBAC and agent cleanup. Required tools: Azure CLI, Terraform, Docker (Linux containers), PowerShell
7.2+, kubectl, kubelogin, Git and **Helm 3**. See [the complete lifecycle](docs/stage-06.md).

Review a destruction plan, then explicitly destroy when ready:

```powershell
pwsh ./scripts/Stop-Lab.ps1
pwsh ./scripts/Stop-Lab.ps1 -Destroy
```

## Implementation and verification stages

| Stage | Deliverable and exercise | Status |
| --- | --- | --- |
| 1 | Terraform AKS/ACR, local lifecycle scripts; inspect identities and RBAC | Code prepared; live verification pending |
| 2 | Reused Python/Java source; multistage images; Helm releases, ACR push; health and rollback exercise | Code prepared; Azure verification pending |
| 3 | Jenkins Helm/JCasC, pinned direct plugins, shared library, dynamic agents; namespace-scoped RBAC and denied-operation exercise | Code prepared; Azure verification pending |
| 4 | Offline external backup, separate key and new-PVC recovery; successful post-restore build | Implemented; kind verified, Azure pending |
| 5 | Bounded metrics/log collection, dashboard and alerts; outage firing/recovery verification | Implemented; kind verified, Azure pending |
| 6 | Complete start/test/backup/stop, retail estimate and Cost Management report; budget exercise | Implemented; Azure lifecycle/billing pending |

See [source review and reuse decisions](docs/source-review.md). The existing local
repository is preserved. Do not describe planned stages as implemented capabilities.

## Repeated learning sessions

`Start-Lab.ps1 -Apply` installs the complete lab and runs verification. With
`-RestoreBackup <folder> -KeyFile <private key path>` it restores previous Jenkins
state. `Test-Lab.ps1` repeats verification without creating infrastructure.
`Stop-Lab.ps1 -Destroy` backs up Jenkins before deletion and checks that both Azure
resource groups are absent. A failed backup blocks destruction. See stage 6 for the
explicit discard option and partial-failure handling. Backup archives and keys are
sensitive local artifacts; do not commit or publish them.

Exercises: [infrastructure](docs/stage-01.md), [Helm/rollback](docs/stage-02.md),
[Jenkins/RBAC](docs/stage-03.md), [recovery](docs/stage-04.md),
[observability/failures](docs/stage-05.md), [lifecycle/costs](docs/stage-06.md).


### Startup safeguards

Before `-Apply`, commit and push all changes to this repository's `origin`.
Startup fetches origin and requires a clean working tree and a published HEAD.
After apply, it waits up to ten minutes for Kubernetes operator authorization,
then checks AKS-to-ACR access before deploying application releases.
A failed apply or later deployment prints the cleanup command and rethrows the
error; it does **not** automatically destroy resources or Jenkins data.
Deletion verification polls for both resource groups for up to five minutes each.

Backups are offline archives with a separately stored controller key, **not
encrypted archives**. Administrator Secret values are only base64 encoded.
Use an encrypted disk/store; file permissions alone do not encrypt a backup.
