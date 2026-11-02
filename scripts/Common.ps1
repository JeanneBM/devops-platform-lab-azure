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
    $settings = @{ location = 'polandcentral'; node_size = 'Standard_D4as_v5' }
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
    if (-not $settings.ContainsKey('subscription_id')) { throw 'Explicit subscription_id is required.' }
    return $settings
}
