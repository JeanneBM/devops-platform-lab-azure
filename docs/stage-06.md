# Stage 6 — complete lifecycle, verification and cost review

## Operator contract

```powershell
# Default mode: Terraform plan only. No paid resources are created.
./scripts/Start-Lab.ps1

# In an explicitly authorized Azure session: price estimate, infrastructure,
# ACR images, Helm applications/Jenkins/observability and complete verification.
./scripts/Start-Lab.ps1 -Apply

# Repeat verification against the running lab without creating infrastructure.
./scripts/Test-Lab.ps1

# Optional deliberate outage/alert firing/resolution in this disposable lab.
./scripts/Test-Lab.ps1 -ExerciseAlerts

# Review deletion, then back up Jenkins, destroy and verify both groups absent.
./scripts/Stop-Lab.ps1
./scripts/Stop-Lab.ps1 -Destroy
```

Start requires PowerShell 7.2+, Git, Terraform, Azure CLI, Docker Linux containers,
kubectl, kubelogin and Helm 3. Tools/Docker are checked before resource creation.
Configuration uses quoted flat string assignments (as in lab.tfvars.example) or a
`.tfvars.json` object. The explicit subscription is checked; review tenant/operator,
regional version, provider registration, VM restrictions and at least 12 vCPU quota
headroom using the stage 1 commands before the first apply. Terraform validation
does not prove those conditions. A failed start can leave billable resources;
use the original state/config to inspect or clean up.

The estimator queries public Azure Retail Prices for the configured Linux PAYG
VM SKU/region, excludes Windows/Spot and requires one unambiguous rate. It adds
an explicitly labelled allowance for other meters. Failure/ambiguity blocks apply
rather than guessing. The estimate is a six-hour planning model, not a quote,
guaranteed cap, tax calculation or proof of availability. Review current ACR,
managed-disk, Standard Load Balancer, IP and egress meters in Pricing Calculator.
Two nodes run all components; Jenkins PVCs and retained recovery PVCs cost extra.

`.local/session.json` records subscription and both group names for later cost queries;
`.local/cost-estimate.json` records the pre-apply estimate. These are private local
records, not portable Terraform state. Preserve `infra/terraform.tfstate` and its
backup until cleanup is verified. Do not commit kubeconfigs, plans or backups.

## Next session with recovered Jenkins

After a successful Stop-Lab backup, retain the printed backup folder and separately
stored key. The next Start creates the fresh environment/controller, then restores
the backup on a new PVC before the complete lab verification:

```powershell
./scripts/Start-Lab.ps1 -Apply -RestoreBackup '<backup folder>' -KeyFile '<matching private .key file>'
```

Recovery checks hashes and the controller image before touching storage. Code/JCasC
reapply the chosen Git revision. A later normal start/deploy preserves an existing
restored claim and administrator Secret rather than switching back to an empty home.
The final test discovers the current administrator Secret from Helm values.
Test a backup on the same core/plugin version before attempting upgrades.

## Stop behavior and failure handling

By default, `Stop-Lab -Destroy` attempts an offline backup when Jenkins is present.
Any backup failure aborts before Terraform apply/destroy. If Jenkins access cannot
be checked, cleanup also stops. For explicitly disposable data or a broken cluster,
`-DiscardJenkinsData` skips that backup; use it only when loss is acceptable.
If no kubeconfig exists (for example an infrastructure-only partial start), no
Jenkins deployment has been performed by this entrypoint and cleanup uses state.
An external/manual deployment is outside that assumption: inspect it first.

Destroy checks both the lab and AKS node resource group with Azure CLI. A missing
or unexpected response is failure, not successful cleanup. Local backups/keys and
session metadata remain. Helm-kept/manual recovery PVCs are included in whole-RG
destruction. Do not assume uninstalling a Helm release removes every retained disk.

## Azure Cost Management exercise

```powershell
# Public pricing read, no Azure login or paid resources:
./scripts/Get-LabCostEstimate.ps1 -Location polandcentral -NodeSize Standard_D4as_v5 -Hours 6

# Read actual month-to-date billed data for both recorded resource groups:
./scripts/Get-LabCostReport.ps1
```

The actual-cost query requires Cost Management read access. It is a read-only query
despite the REST POST verb. Returned column metadata defines the currency and row
values. Reporting can lag and deleted-group costs can appear after cleanup; zero or
empty early results are not evidence of no charges. Month-to-date data can include
several sessions when names are reused. Record start/stop times to compare sessions.

In Cost Management, review both groups and project tags, compare estimates with actual
charges, and set a small monthly budget with actual/forecast thresholds. Confirm any
notification recipients yourself. No email, Slack message or budget notification is
sent by this code. A budget notifies; it is not a spending stop. Keep lab sessions short
and verify destruction instead of relying on a budget to delete resources.

## Final CI versus Azure evidence

CI checks Terraform schema/format, PowerShell parsing and safeguards, synthetic cost
arithmetic, application behavior, real Helm deployments, a real Jenkins shared-library
dynamic-agent build, offline backup/new-PVC restoration, and a subsequent build. The
full lab job then verifies applications, recovered Jenkins, actual collected metrics/logs,
the provisioned dashboard, and outage alert firing/resolution in one kind cluster.

No paid Azure resources are created by CI. A first live session must still prove Azure
credentials/tenant, quota/SKU availability, ACR push/pull, Entra authorization and API
allowlist, managed-csi disk behavior, teardown of both groups, and actual billing.
Windows/PowerShell client behavior also needs a real workstation check. Record those
facts separately; do not label a kind run as an AKS deployment.

References: [Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices),
[Cost Management query](https://learn.microsoft.com/en-us/rest/api/cost-management/query/usage?view=rest-cost-management-2023-03-01).
