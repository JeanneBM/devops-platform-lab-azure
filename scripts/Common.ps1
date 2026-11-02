Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LabRoot = Split-Path $PSScriptRoot -Parent
$script:InfraRoot = Join-Path $script:LabRoot 'infra'

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
