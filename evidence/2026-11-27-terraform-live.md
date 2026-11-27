# Azure infrastructure lifecycle — 27 November 2026

## Provenance and scope

This record summarizes a terminal capture supplied by the repository owner from
a Windows workstation running Git Bash. The uploaded capture includes apply,
Azure CLI inspection, the post-apply plan, destruction progress and the final
cleanup result. A [redacted copy of that capture](2026-11-27-terraform-live.log)
and its [SHA-256 manifest](2026-11-27-terraform-live.log.sha256) accompany this
summary. No independent Azure account connection was used by the reviewer.

The capture's echoed pasted command is visibly truncated/garbled. The operation
output from the start timestamp through the final timestamp is readable, but
the capture is not a byte-for-byte copy of the runner source or the original
`.local/terraform-session-*.log` file. The raw session-log file was not supplied.
Claims below refer to the output present in the uploaded capture.

### Capture provenance and redaction

| Artifact | SHA-256 |
| --- | --- |
| Original uploaded capture, 38,095 bytes; kept private | `f74eff3e70bf09169aa75524d97553cd6ec449074206d02cc8c7e86390309d88` |
| Redacted UTF-8/LF copy, 34,943 bytes | `9952a4b21ec765c927e2b04de2087620c966e1216fbed6578dd2e4cf72ba8676` |

The public copy retains the uploaded capture's lines and result messages while
masking account UUIDs, full and abbreviated subscription path components,
encoded client-config IDs, the operator IPv4 address, workstation/user prompt
and unique lab/DNS suffixes. CRLF line endings were normalized to LF. SHA-256
identifies the reviewed files; it does not authenticate their execution.

Verify the committed redacted copy from this directory with:

```bash
sha256sum -c 2026-11-27-terraform-live.log.sha256
```

The previously reported checkout was
`8e363351b4abf3e3580d79bc255a40eba0084fc0`, with the reviewed Windows provider
checksum addition. No new source or binary-plan hash was supplied at apply time.
The executed plan used the local `node_size = "Standard_D4as_v6"` override;
the repository's default remains `Standard_D4as_v5`.

| Item | Observed value |
| --- | --- |
| Terraform / provider | 1.9.8 / AzureRM 4.45.1 |
| Region / Kubernetes | polandcentral / 1.37.1 |
| Node pool | Two Standard_D4as_v6 Linux nodes; 64 GiB managed OS disk each |
| Start | 2026-11-27 15:59:49 +01:00 |
| End | 2026-11-27 16:12:12 +01:00 |
| Elapsed | 12 minutes 23 seconds; script rounded up to 13 minutes |
| Runner | Local Bash session with an EXIT cleanup trap; direct Terraform and Azure CLI calls |

This session did not run the full `Start-Lab.ps1 -Apply` application/Jenkins
workflow. No application images, Helm releases or Jenkins data were created by
the runner.

## Quota and planning

All six checked resource providers were registered. The original DASv5-family
quota was zero, so the original size was not applied. In the owner's output,
the Dav6-family quota and total regional vCPU quota each had limit 10 with zero
used. The chosen D4as_v6 SKU had no reported SKU restrictions. The revised saved
plan reported **7 to add, 0 to change, 0 to destroy**.

Before applying, the runner required the default Terraform workspace, absence
of the local `infra/terraform.tfstate`, and absence of both target resource
groups. The subscription was read from the local variable file.

## Observed results

| Check | Result |
| --- | --- |
| Saved-plan apply | `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.` |
| AKS provisioning | Succeeded; two Standard_D4as_v6 nodes configured |
| AKS authentication settings | Azure RBAC and Workload Identity reported true |
| ACR | Succeeded; Basic; administrator credentials disabled |
| Role assignments | Four observed at the intended AKS/ACR resource scopes |
| Post-apply plan | **0 to add, 1 to change, 0 to destroy**; zero-diff check failed |
| ACR deletion | Destruction complete after 11 seconds |
| AKS deletion | Destruction complete after 5 minutes 49 seconds |
| Lab resource group deletion | Destruction complete after 47 seconds |
| Destruction | `Destroy complete! Resources: 7 destroyed.` |
| Azure group-absence checks | `CLEANUP VERIFIED: obie grupy usuniete.` |

The four roles were kubelet **AcrPull**, operator **AcrPush**, operator **Azure
Kubernetes Service Cluster User Role**, and operator **Azure Kubernetes Service
RBAC Cluster Admin**. Listing assignments proves their presence and scopes;
it does not prove an authenticated Kubernetes operation succeeded.

## Convergence finding and proposed correction

After apply, the read-back default node pool contained this undeclared block:

```hcl
upgrade_settings {
  drain_timeout_in_minutes      = 0
  max_surge                     = "10%"
  node_soak_duration_in_minutes = 0
}
```

Terraform proposed removing the block. Its detailed plan exit code therefore
triggered the runner's cleanup trap, and the successful idempotency message was
not printed. This was not an apply failure.

A later local change explicitly declares `upgrade_settings.max_surge = "10%"`
in the default node pool, matching the observed value. It has not been applied
or verified by a second live post-apply plan. Zero-diff convergence remains open.
Surge capacity during a future upgrade must be checked separately from initial
creation quota; this session performed no upgrade.

Local follow-up checks used Terraform 1.9.8: `fmt -check` and
`init -backend=false -input=false -lockfile=readonly` passed, as did
`git diff --check`. Schema validation could not complete because the review
environment denied the provider's local Unix socket (`socket: operation not
permitted`). This is an environment limitation, not a successful validation
result. No Azure credentials or live apply were used for these follow-up checks.

## Cost and evidence limits

The live retail lookup for Poland Central returned USD 0.22 per node-hour for
Linux D4as_v6 PAYG, excluding Spot/Low Priority and Windows. Charging both nodes
for the entire rounded 13-minute session would be approximately USD 0.0953 in
compute alone; actual meter times differ. A planning estimate of PLN 1–2 net,
with PLN 3 reserved, includes allowance for short-lived registry, disk and
network charges. It is not a measured bill or a guaranteed spending cap.

Check Cost Management for the session date and both deleted resource groups.
Pay-as-you-go usage can take up to 72 hours to appear:
[Microsoft cost-data guidance](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/understand-cost-mgt-data).

The raw capture includes account identifiers, public IP and unique resource
names; the accompanying copy masks them as described above. Raw plans, local
variables, state and the original session-log path are Git-ignored on the
owner's workstation; those files were not collected for this record. Preserve
the originals for review. Do not infer Azure application, node-readiness,
effective Kubernetes RBAC, full lifecycle-script or billing validation from
this infrastructure run.
