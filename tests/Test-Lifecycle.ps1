#Requires -Version 7.2
# Execute lifecycle scripts against fake executables in an isolated temporary lab.
# This test must never contact Azure or Terraform.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$global:LabCalls = @()
$global:FailLabPlan = $false
function global:az { $global:LASTEXITCODE = 0 }
function global:terraform {
    $global:LabCalls += ,@($args)
    $global:LASTEXITCODE = 0
    if ($global:FailLabPlan -and $args -contains 'plan') { $global:LASTEXITCODE = 1 }
}
function Assert-Lab([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
try {
    New-Item -ItemType Directory -Path (Join-Path $temp 'infra') -Force | Out-Null
    Copy-Item (Join-Path $root 'scripts') -Destination $temp -Recurse
    $config = Join-Path $temp 'lab.tfvars'
    Set-Content $config 'subscription_id = "11111111-1111-1111-1111-111111111111"'
    $start = Join-Path $temp 'scripts/Start-Lab.ps1'
    $stop = Join-Path $temp 'scripts/Stop-Lab.ps1'
    & $start -ConfigFile $config
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains 'apply' }).Count -eq 0) 'Default start applied resources!'
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains 'plan' }).Count -eq 1) 'Default start did not plan.'

    $global:LabCalls = @()
    $global:FailLabPlan = $true
    $caught = $false
    try { & $start -ConfigFile $config -Apply } catch { $caught = $true }
    Assert-Lab $caught 'Plan failure was ignored.'
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains 'apply' }).Count -eq 0) 'Failed plan was applied!'
    $global:FailLabPlan = $false

    $global:LabCalls = @()
    $caught = $false
    try { & $stop -ConfigFile $config -Destroy } catch { $caught = $true }
    Assert-Lab $caught 'Missing state did not stop cleanup.'
    Assert-Lab ($global:LabCalls.Count -eq 0) 'Cleanup invoked Terraform without state.'

    Set-Content (Join-Path $temp 'infra/terraform.tfstate') '{}'
    & $stop -ConfigFile $config
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains 'apply' }).Count -eq 0) 'Default stop destroyed resources!'
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains '-destroy' }).Count -eq 1) 'No destroy plan.'
    Write-Host 'Lifecycle safety tests passed (mock executables; no Azure calls).'
} finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item function:az, function:terraform -ErrorAction SilentlyContinue
    Remove-Variable LabCalls, FailLabPlan -Scope Global -ErrorAction SilentlyContinue
}
