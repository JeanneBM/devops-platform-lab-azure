#Requires -Version 7.2
# Execute lifecycle scripts against fake executables in an isolated temporary lab.
# This test must never contact Azure or Terraform.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$global:LabCalls = @()
$global:FailLabPlan = $false
$global:FailLabApply = $false
$global:FailLabOutput = $false
function global:az { $global:LASTEXITCODE = 0; if ($args -contains 'group' -and $args -contains 'exists') { 'false' } }
function global:docker { $global:LASTEXITCODE = 0 }
function global:kubectl { $global:LASTEXITCODE = 0; 'statefulset.apps/jenkins' }
function global:kubelogin { $global:LASTEXITCODE = 0 }
function global:helm { $global:LASTEXITCODE = 0; 'v3.17.3' }
function global:git {
    $global:LASTEXITCODE = 0
    if ($args -contains 'status') { return }
    if ($args -contains 'get-url') { return 'https://github.com/JeanneBM/devops-platform-lab-azure.git' }
    if ($args -contains 'fetch') { return }
    if ($args -contains 'branch') { return 'origin/main' }
    '1111111111111111111111111111111111111111'
}
function global:terraform {
    $global:LabCalls += ,@($args)
    $global:LASTEXITCODE = 0
    if ($global:FailLabPlan -and $args -contains 'plan') { $global:LASTEXITCODE = 1 }
    if ($global:FailLabApply -and $args -contains 'apply') { $global:LASTEXITCODE = 1 }
    if ($global:FailLabOutput -and $args -contains 'output') { $global:LASTEXITCODE = 1 }
}
function Assert-Lab([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
try {
    New-Item -ItemType Directory -Path (Join-Path $temp 'infra') -Force | Out-Null
    Copy-Item (Join-Path $root 'scripts') -Destination $temp -Recurse
    $config = Join-Path $temp 'lab.tfvars'
    Set-Content $config @('subscription_id = "11111111-1111-1111-1111-111111111111"', 'suffix = "unit1234"')
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
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains 'plan' }).Count -eq 1) 'Expected the mock plan itself to be reached.'
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains 'apply' }).Count -eq 0) 'Failed plan was applied!'
    $global:FailLabPlan = $false

    # A partially failed apply must retain its error and show the cleanup command.
    Set-Content (Join-Path $temp 'scripts/Get-LabCostEstimate.ps1') 'param($Location, $NodeSize); @{ estimated = 0 }'
    $global:FailLabApply = $true
    $warnings = @()
    $caught = $false
    try { & $start -ConfigFile $config -Apply -WarningVariable warnings } catch { $caught = $_ -match 'terraform failed' }
    Assert-Lab $caught 'Apply failure was swallowed.'
    Assert-Lab (($warnings -join ' ') -match 'Stop-Lab.ps1') 'Apply failure did not print cleanup instructions.'
    $global:FailLabApply = $false
    $global:FailLabOutput = $true
    $warnings = @()
    $caught = $false
    try { & $start -ConfigFile $config -Apply -WarningVariable warnings } catch { $caught = $_ -match 'terraform failed' }
    Assert-Lab $caught 'Post-apply failure was swallowed.'
    Assert-Lab (($warnings -join ' ') -match 'Stop-Lab.ps1') 'Post-apply failure did not print cleanup instructions.'
    $global:FailLabOutput = $false

    $global:LabCalls = @()
    $caught = $false
    try { & $stop -ConfigFile $config -Destroy } catch { $caught = $true }
    Assert-Lab $caught 'Missing state did not stop cleanup.'
    Assert-Lab ($global:LabCalls.Count -eq 0) 'Cleanup invoked Terraform without state.'

    Set-Content (Join-Path $temp 'infra/terraform.tfstate') '{}'
    & $stop -ConfigFile $config
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains 'apply' }).Count -eq 0) 'Default stop destroyed resources!'
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains '-destroy' }).Count -eq 1) 'No destroy plan.'
    New-Item -ItemType Directory -Force (Join-Path $temp '.local') | Out-Null
    Set-Content (Join-Path $temp '.local/aks.kubeconfig') 'fake'
    Set-Content (Join-Path $temp 'scripts/Backup-Jenkins.ps1') "throw 'simulated backup failure'"
    $global:LabCalls = @()
    $caught = $false
    try { & $stop -ConfigFile $config -Destroy } catch { $caught = $_.Exception.Message -match 'simulated backup failure' }
    Assert-Lab $caught 'Expected backup failure before destruction.'
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains 'apply' }).Count -eq 0) 'Destroy proceeded after failed backup!'
    & $stop -ConfigFile $config -Destroy -DiscardJenkinsData
    Assert-Lab (@($global:LabCalls | Where-Object { $_ -contains 'apply' }).Count -eq 1) 'Explicit discard did not execute the mock destroy plan.'
    Write-Host 'Lifecycle safety tests passed (mock executables; no Azure calls).'
} finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item function:az, function:terraform, function:docker, function:kubectl, function:kubelogin, function:helm, function:git -ErrorAction SilentlyContinue
    Remove-Variable LabCalls, FailLabPlan, FailLabApply, FailLabOutput -Scope Global -ErrorAction SilentlyContinue
}

