#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot '../lab.tfvars'),
    [switch]$Apply
)
. (Join-Path $PSScriptRoot 'Common.ps1')
if ($Apply) {
    # Fail before infrastructure creation if local application tools are missing.
    Assert-LabTools @('docker', 'kubectl', 'kubelogin', 'helm')
    Assert-LabHelm
    Invoke-LabNative 'docker' @('info')
}
$config = Initialize-Lab $ConfigFile
$plan = Join-Path $script:InfraRoot 'create.tfplan'
if (Test-Path -LiteralPath $plan) { Remove-Item -LiteralPath $plan }
Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'plan', '-input=false', "-var-file=$config", "-out=$plan")
if (-not $Apply) {
    Write-Host 'PLAN ONLY: no paid resources created. Review docs/costs.md and the plan.'
    Write-Host 'An explicit Start-Lab.ps1 -Apply invocation creates billable resources.'
    return
}
Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'apply', '-input=false', $plan)
Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'output')
$outputs = Get-LabOutputs
$subscription = $outputs.subscription_id.value
$cluster = $outputs.cluster_name.value
$rg = $outputs.resource_group_name.value
$local = Join-Path $script:LabRoot '.local'
New-Item -ItemType Directory -Force $local | Out-Null
$kube = Join-Path $local 'aks.kubeconfig'
Invoke-LabNative 'az' @('account', 'set', '--subscription', $subscription)
Invoke-LabNative 'az' @('aks', 'get-credentials', '--subscription', $subscription,
    '--resource-group', $rg, '--name', $cluster, '--file', $kube, '--overwrite-existing')
Invoke-LabNative 'kubelogin' @('convert-kubeconfig', '-l', 'azurecli', '--kubeconfig', $kube)
$tag = 'session-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')
& (Join-Path $PSScriptRoot 'Publish-Images.ps1') -SubscriptionId $subscription `
    -AcrName $outputs.acr_name.value -Registry $outputs.acr_login_server.value -ImageTag $tag
& (Join-Path $PSScriptRoot 'Deploy-Applications.ps1') -Registry $outputs.acr_login_server.value `
    -ImageTag $tag -Kubeconfig $kube
& (Join-Path $PSScriptRoot 'Test-Applications.ps1') -Kubeconfig $kube
Write-Host "Applications deployed and verified with image tag $tag. Jenkins is not installed yet."
