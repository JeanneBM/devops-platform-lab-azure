Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LabRoot = Split-Path $PSScriptRoot -Parent
$script:InfraRoot = Join-Path $script:LabRoot 'infra'

function Assert-LabTools {
    param([string[]]$Tools)
    foreach ($tool in $Tools) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Install $tool and reopen PowerShell."
        }
    }
}

function Assert-LabHelm {
    $version = & helm version --short
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^v3\.') {
        throw 'This lab uses Helm 3. Install Helm 3 before deploying.'
    }
}

function Get-LabOutputs {
    $json = & terraform "-chdir=$script:InfraRoot" output -json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Terraform outputs.' }
    return (($json -join "`n") | ConvertFrom-Json)
}

function Invoke-LabNative {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed (exit $LASTEXITCODE)." }
}

function Initialize-Lab {
    param([string]$ConfigFile)
    foreach ($tool in @('az', 'terraform')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Install $tool and reopen PowerShell."
        }
    }
    $resolved = (Resolve-Path -LiteralPath $ConfigFile).Path
    $config = Get-Content -LiteralPath $resolved -Raw
    if ($config -match '00000000-0000-0000-0000-000000000000|203\.0\.113\.10|REPLACE_WITH|suffix\s*=\s*"replace"') {
        throw 'Replace all placeholders in your configuration first.'
    }
    # Fail before init/plan if Azure CLI is not authenticated. Provider uses explicit subscription_id.
    Invoke-LabNative 'az' @('account', 'show', '--output', 'none')
    Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'init', '-input=false')
    Invoke-LabNative 'terraform' @("-chdir=$script:InfraRoot", 'validate')
    return $resolved
}


function Get-LabJenkinsValues {
    param([string]$Kube)
    $raw = & helm list --kubeconfig $Kube --namespace jenkins --filter '^jenkins$' --output json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Jenkins Helm release.' }
    if (@((($raw -join "`n") | ConvertFrom-Json)).Count -eq 0) { return @{} }
    $raw = & helm get values jenkins --kubeconfig $Kube --namespace jenkins --output json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Jenkins values.' }
    $values = ($raw -join "`n") | ConvertFrom-Json -AsHashtable
    if ($null -eq $values) { return @{} }
    return $values
}

function Get-LabJenkinsAdminSecret {
    param([string]$Kube)
    $values = Get-LabJenkinsValues $Kube
    if ($values.ContainsKey('controller') -and $values.controller.ContainsKey('admin') -and $values.controller.admin.ContainsKey('existingSecret') -and $values.controller.admin.existingSecret) {
        return $values.controller.admin.existingSecret
    }
    return 'jenkins'
}


function Read-LabSettings {
    param([string]$Path)
    $settings = @{ location = 'polandcentral'; node_size = 'Standard_D4as_v5'; prefix = 'devopslab' }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($Path.EndsWith('.json')) {
        $parsed = $raw | ConvertFrom-Json -AsHashtable
        foreach ($key in $parsed.Keys) { $settings[$key] = $parsed[$key] }
    } else {
        foreach ($line in ($raw -split "`n")) {
            if ($line.Trim() -eq '' -or $line.Trim().StartsWith('#')) { continue }
            if ($line -notmatch '^\s*([a-z_]+)\s*=\s*"([^"\r\n]+)"\s*(?:#.*)?$') {
                throw 'Lifecycle configuration must use flat quoted string assignments, or a .tfvars.json object.'
            }
            $settings[$Matches[1]] = $Matches[2]
        }
    }
    if (-not $settings.ContainsKey('subscription_id') -or -not $settings.ContainsKey('suffix')) { throw 'Explicit subscription_id and suffix are required.' }
    return $settings
}


# This repository URL is also hard-coded in the Jenkins SCM configuration.
function Assert-LabPublishedSource {
    $sourceRef = & git -C $script:LabRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $sourceRef -notmatch '^[0-9a-f]{40}$') {
        throw 'Run from a Git checkout with a committed Jenkins pipeline.'
    }
    $dirty = & git -C $script:LabRoot status --porcelain
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Commit and push all working tree changes before -Apply.' }
    $remote = & git -C $script:LabRoot remote get-url origin
    if ($LASTEXITCODE -ne 0 -or $remote -notmatch '^(https://github[.]com/|git@github[.]com:)JeanneBM/devops-platform-lab-azure([.]git)?$') {
        throw 'origin must point to JeanneBM/devops-platform-lab-azure, the Jenkins SCM repository.'
    }
    Invoke-LabNative 'git' @('-C', $script:LabRoot, 'fetch', '--prune', 'origin', '+refs/heads/*:refs/remotes/origin/*')
    $published = & git -C $script:LabRoot branch -r --contains $sourceRef --list 'origin/*'
    if ($LASTEXITCODE -ne 0 -or -not $published) { throw 'Push HEAD to a branch on origin before -Apply.' }
    return "$sourceRef".Trim()
}

function Wait-LabCheck {
    param(
        [Parameter(Mandatory)][scriptblock]$Check,
        [Parameter(Mandatory)][string]$Description,
        [ValidateRange(0, 3600)][int]$TimeoutSeconds = 600,
        [ValidateRange(1, 60)][int]$IntervalSeconds = 15
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (& $Check) { return }
        if ([DateTime]::UtcNow -ge $deadline) { throw "Timed out: $Description." }
        Write-Host "Waiting: $Description"
        Start-Sleep -Seconds $IntervalSeconds
    } while ($true)
}

function Wait-LabClusterAccess {
    param([string]$Kubeconfig)
    Wait-LabCheck -Description 'AKS operator RBAC propagation (up to 10 minutes)' -Check {
        $answer = & kubectl --kubeconfig $Kubeconfig --request-timeout=15s auth can-i create namespaces --all-namespaces 2>$null
        return ($LASTEXITCODE -eq 0 -and ($answer -join '').Trim() -eq 'yes')
    }
}

function Wait-LabAcrAccess {
    param([string]$Subscription, [string]$ResourceGroup, [string]$Cluster, [string]$Registry)
    # check-acr creates its own kubeconfig; the lab kubeconfig conversion does
    # not reach it. kubelogin supports AAD_LOGIN_METHOD for this child process.
    $previousLoginMethod = [Environment]::GetEnvironmentVariable('AAD_LOGIN_METHOD', 'Process')
    try {
        $env:AAD_LOGIN_METHOD = 'azurecli'
        Wait-LabCheck -Description 'AKS kubelet access to ACR (up to 10 minutes plus an in-flight diagnostic)' -Check {
            & az aks check-acr --subscription $Subscription --resource-group $ResourceGroup --name $Cluster --acr $Registry --only-show-errors | Out-Host
            return ($LASTEXITCODE -eq 0)
        }
    } finally {
        [Environment]::SetEnvironmentVariable('AAD_LOGIN_METHOD', $previousLoginMethod, 'Process')
    }
}

function Wait-LabGroupDeleted {
    param([string]$Subscription, [string]$Group)
    Wait-LabCheck -Description "resource group deletion: $Group (up to 5 minutes)" -TimeoutSeconds 300 -Check {
        $exists = & az group exists --subscription $Subscription --name $Group --output tsv
        return ($LASTEXITCODE -eq 0 -and ($exists -join '').Trim() -eq 'false')
    }
}
