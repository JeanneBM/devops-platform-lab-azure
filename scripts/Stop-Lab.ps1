#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot '../lab.tfvars'),
    [switch]$Destroy,
    [switch]$DiscardJenkinsData,
    [string]$BackupDirectory = (Join-Path $PSScriptRoot '../.backups'),
    [string]$KeyDirectory = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.devops-lab-keys')
)
. (Join-Path $PSScriptRoot 'Common.ps1')
# Never initialize an empty state and report a misleading successful cleanup.
$state = Join-Path $script:InfraRoot 'terraform.tfstate'
if (-not (Test-Path -LiteralPath $state)) {
    throw 'Local Terraform state is missing. Restore the original state before cleanup; see docs/stage-01.md.'
}
$config = Initialize-Lab $ConfigFile
$plan = Join-Path $script:InfraRoot 'destroy.tfplan'
if (Test-Path -LiteralPath $plan) { Remove-Item -LiteralPath $plan }
Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'plan', '-destroy', '-input=false', "-var-file=$config", "-out=$plan")
if (-not $Destroy) {
    Write-Host 'PLAN ONLY: resources still exist and can still incur charges.'
    Write-Host 'Back up Jenkins outside the cluster (once installed) before using -Destroy.'
    return
}
# Derive the known names from the original config even after a partial apply,
# when Terraform may not yet have produced all outputs.
$settings = Read-LabSettings $config
$subscription = $settings.subscription_id
$groups = @("rg-$($settings.prefix)-$($settings.suffix)", "rg-$($settings.prefix)-$($settings.suffix)-nodes")
$kube = Join-Path $script:LabRoot '.local/aks.kubeconfig'
if (-not $DiscardJenkinsData -and (Test-Path $kube)) {
    $jenkins = & kubectl --kubeconfig $kube -n jenkins get statefulset jenkins --ignore-not-found -o name
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Jenkins. Restore access or explicitly use -DiscardJenkinsData for disposable data.' }
    if ($jenkins) {
        $backup = & (Join-Path $PSScriptRoot 'Backup-Jenkins.ps1') -Kubeconfig $kube -BackupDirectory $BackupDirectory -KeyDirectory $KeyDirectory
        Write-Host "Backup saved before destruction: $backup"
    }
}
if ($DiscardJenkinsData) { Write-Warning 'Explicitly discarding Jenkins data without a new backup.' }
Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'apply', '-input=false', $plan)
foreach ($group in $groups) {
    $exists = & az group exists --subscription $subscription --name $group --output tsv
    if ($LASTEXITCODE -ne 0 -or ($exists -join '').Trim() -ne 'false') {
        throw "Cleanup not verified for $group. Investigate remaining resources and charges."
    }
}
Write-Host 'CLEANUP VERIFIED: both resource groups are absent. Backup files and keys remain outside Azure.'
Write-Host 'Run Get-LabCostReport.ps1 after billing data arrives; session.json is retained.' 
