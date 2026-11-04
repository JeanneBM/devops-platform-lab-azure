#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot '../lab.tfvars'),
    [switch]$Apply,
    [string]$RestoreBackup = '',
    [string]$KeyFile = '' 
)
. (Join-Path $PSScriptRoot 'Common.ps1')
if ($Apply) {
    # Fail before infrastructure creation if local application tools are missing.
    Assert-LabTools @('docker', 'kubectl', 'kubelogin', 'helm', 'git')
    Assert-LabHelm
    Invoke-LabNative 'docker' @('info')
    $sourceRef = Assert-LabPublishedSource
}
if ([bool]$RestoreBackup -ne [bool]$KeyFile) { throw 'RestoreBackup and KeyFile must be supplied together.' }
if ($RestoreBackup) {
    $RestoreBackup = (Resolve-Path $RestoreBackup).Path
    $KeyFile = (Resolve-Path $KeyFile).Path
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
$settings = Read-LabSettings $config
Invoke-LabNative 'az' @('account', 'show', '--subscription', $settings.subscription_id, '--output', 'none')
$estimate = & (Join-Path $PSScriptRoot 'Get-LabCostEstimate.ps1') -Location $settings.location -NodeSize $settings.node_size
$estimate | Format-List | Out-Host
$local = Join-Path $script:LabRoot '.local'
New-Item -ItemType Directory -Force $local | Out-Null
$estimate | ConvertTo-Json | Set-Content (Join-Path $local 'cost-estimate.json')
try {
Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'apply', '-input=false', $plan)
Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'output')
$outputs = Get-LabOutputs
$subscription = $outputs.subscription_id.value
$cluster = $outputs.cluster_name.value
$rg = $outputs.resource_group_name.value
$local = Join-Path $script:LabRoot '.local'
New-Item -ItemType Directory -Force $local | Out-Null
$kube = Join-Path $local 'aks.kubeconfig'
@{
    subscriptionId = $subscription; resourceGroup = $rg
    nodeResourceGroup = $outputs.node_resource_group_name.value
    cluster = $cluster; sourceRef = $sourceRef; startedUtc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content (Join-Path $local 'session.json')
Invoke-LabNative 'az' @('account', 'set', '--subscription', $subscription)
Wait-LabCheck -Description 'AKS credential-download role propagation (up to 10 minutes)' -Check {
    & az aks get-credentials --subscription $subscription --resource-group $rg --name $cluster --file $kube --overwrite-existing | Out-Host
    return ($LASTEXITCODE -eq 0)
}
Invoke-LabNative 'kubelogin' @('convert-kubeconfig', '-l', 'azurecli', '--kubeconfig', $kube)
Wait-LabClusterAccess -Kubeconfig $kube
$tag = 'session-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')
& (Join-Path $PSScriptRoot 'Publish-Images.ps1') -SubscriptionId $subscription `
    -AcrName $outputs.acr_name.value -Registry $outputs.acr_login_server.value -ImageTag $tag
Wait-LabAcrAccess -Subscription $subscription -ResourceGroup $rg -Cluster $cluster -Registry $outputs.acr_login_server.value
& (Join-Path $PSScriptRoot 'Deploy-Applications.ps1') -Registry $outputs.acr_login_server.value `
    -ImageTag $tag -Kubeconfig $kube
& (Join-Path $PSScriptRoot 'Deploy-Jenkins.ps1') -Kubeconfig $kube -SourceRef $sourceRef
if ($RestoreBackup) {
    & (Join-Path $PSScriptRoot 'Restore-Jenkins.ps1') -Kubeconfig $kube -BackupFolder $RestoreBackup -KeyFile $KeyFile -SourceRef $sourceRef | Out-Host
}
& (Join-Path $PSScriptRoot 'Deploy-Observability.ps1') -Kubeconfig $kube
& (Join-Path $PSScriptRoot 'Test-Lab.ps1') -Kubeconfig $kube
Write-Host "Applications, Jenkins and observability verified. Application tag: $tag; pipeline commit: $sourceRef."


} catch {
    Write-Warning 'ZASOBY MOGĄ NADAL DZIAŁAĆ I NALICZAĆ KOSZTY. Start nie wycofuje infrastruktury.'
    Write-Warning "Cleanup: ./scripts/Stop-Lab.ps1 -ConfigFile '$config' -Destroy"
    Write-Warning 'If cluster access or backup fails, use -DiscardJenkinsData only for disposable Jenkins data.'
    throw
}
