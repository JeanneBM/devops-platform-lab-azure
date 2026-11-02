#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot '../lab.tfvars'),
    [switch]$Destroy
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
Write-Warning 'Destroy removes the Jenkins PVC and data. Automated external backup is not implemented yet.'
Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'apply', '-input=false', $plan)
Write-Host 'Terraform destroy finished. Verify both resource groups are gone; see docs/stage-01.md.'
