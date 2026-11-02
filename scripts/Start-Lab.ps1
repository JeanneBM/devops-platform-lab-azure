#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot '../lab.tfvars'),
    [switch]$Apply
)
. (Join-Path $PSScriptRoot 'Common.ps1')
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
Write-Host 'Infrastructure created. Stage 1 does not install applications or Jenkins.'
Write-Host 'Run the verification exercise in docs/stage-01.md.'
