# No Azure access: exercise success, denial, timeout and CLI-error paths.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/Common.ps1')
function Assert-Test($Condition, $Message) { if (-not $Condition) { throw $Message } }
$global:Checks = 0
$originalLoginMethod = [Environment]::GetEnvironmentVariable('AAD_LOGIN_METHOD', 'Process')
function global:Start-Sleep { param($Seconds) }
try {
    Wait-LabCheck -Description 'eventual success' -Check { $global:Checks++; return ($global:Checks -eq 3) }
    Assert-Test ($global:Checks -eq 3) 'Did not retry readiness.'
    $caught = $false
    try { Wait-LabCheck -Description 'denied' -TimeoutSeconds 0 -Check { $false } } catch { $caught = $_ -match 'Timed out' }
    Assert-Test $caught 'Denied check did not time out.'
    $global:Checks = 0
    function global:kubectl {
        $global:Checks++
        if ($global:Checks -eq 1) { $global:LASTEXITCODE = 1; 'no' }
        else { $global:LASTEXITCODE = 0; 'yes' }
    }
    Wait-LabClusterAccess -Kubeconfig fake
    Assert-Test ($global:Checks -eq 2) '403 was not retried.'
    $global:Checks = 0
    function global:az {
        $global:Checks++
        if ($args -contains 'check-acr') {
            Assert-Test ($env:AAD_LOGIN_METHOD -eq 'azurecli') 'ACR diagnostic did not inherit Azure CLI authentication.'
            $global:LASTEXITCODE = $(if ($global:Checks -eq 1) { 1 } else { 0 })
        } else {
            $global:LASTEXITCODE = 0
            if ($global:Checks -eq 1) { 'true' } else { 'false' }
        }
    }
    $env:AAD_LOGIN_METHOD = 'devicecode'
    Wait-LabAcrAccess -Subscription fake -ResourceGroup fake -Cluster fake -Registry fake
    Assert-Test ($global:Checks -eq 2) 'Failed ACR diagnostic was not retried.'
    Assert-Test ($env:AAD_LOGIN_METHOD -eq 'devicecode') 'Caller login method was not restored after success.'
    Remove-Item Env:AAD_LOGIN_METHOD -ErrorAction SilentlyContinue
    Wait-LabAcrAccess -Subscription fake -ResourceGroup fake -Cluster fake -Registry fake
    Assert-Test ($null -eq [Environment]::GetEnvironmentVariable('AAD_LOGIN_METHOD', 'Process')) 'Absent login override was not restored.'
    $env:AAD_LOGIN_METHOD = 'interactive'
    function global:az {
        Assert-Test ($env:AAD_LOGIN_METHOD -eq 'azurecli') 'ACR exception path did not inherit Azure CLI authentication.'
        throw 'simulated diagnostic failure'
    }
    $caught = $false
    try { Wait-LabAcrAccess -Subscription fake -ResourceGroup fake -Cluster fake -Registry fake } catch { $caught = $_ -match 'simulated diagnostic failure' }
    Assert-Test $caught 'Diagnostic exception was swallowed.'
    Assert-Test ($env:AAD_LOGIN_METHOD -eq 'interactive') 'Caller login method was not restored after failure.'
    function global:az {
        $global:Checks++
        $global:LASTEXITCODE = 0
        if ($global:Checks -eq 1) { 'true' } else { 'false' }
    }
    $global:Checks = 0
    Wait-LabGroupDeleted -Subscription fake -Group fake
    Assert-Test ($global:Checks -eq 2) 'Pending group deletion was not retried.'
    $global:Dirty = $false
    $global:Published = $true
    function global:git {
        $global:LASTEXITCODE = 0
        if ($args -contains 'status') { if ($global:Dirty) { ' M Jenkinsfile' }; return }
        if ($args -contains 'get-url') { return 'https://github.com/JeanneBM/devops-platform-lab-azure.git' }
        if ($args -contains 'fetch') { return }
        if ($args -contains 'branch') { if ($global:Published) { 'origin/main' }; return }
        '1111111111111111111111111111111111111111'
    }
    Assert-Test ((Assert-LabPublishedSource) -eq '1111111111111111111111111111111111111111') 'Published HEAD rejected.'
    foreach ($case in @('dirty', 'unpublished')) {
        $global:Dirty = $case -eq 'dirty'
        $global:Published = $case -ne 'unpublished'
        $caught = $false
        try { Assert-LabPublishedSource } catch { $caught = $true }
        Assert-Test $caught "Unsafe source accepted: $case"
    }
    Write-Host 'Readiness and Git preflight tests passed (no network).'
} finally {
    if ($null -eq $originalLoginMethod) {
        Remove-Item Env:AAD_LOGIN_METHOD -ErrorAction SilentlyContinue
    } else {
        [Environment]::SetEnvironmentVariable('AAD_LOGIN_METHOD', $originalLoginMethod, 'Process')
    }
    Remove-Item function:Start-Sleep, function:kubectl, function:az, function:git -ErrorAction SilentlyContinue
    Remove-Variable Checks, Dirty, Published -Scope Global -ErrorAction SilentlyContinue
}
