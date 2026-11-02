#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$AcrName,
    [Parameter(Mandatory)][string]$Registry,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')][string]$ImageTag
)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabTools @('az', 'docker')
Invoke-LabNative 'docker' @('info')
# Entra authentication; no registry admin password or committed token.
Invoke-LabNative 'az' @('acr', 'login', '--subscription', $SubscriptionId, '--name', $AcrName)
foreach ($app in @(
    @{ Name = 'pycalculator'; Context = 'src/python' },
    @{ Name = 'g4g7singleton'; Context = 'src/java' }
)) {
    $image = "$Registry/$($app.Name):$ImageTag"
    # AKS nodes are amd64 even when the developer workstation uses ARM.
    Invoke-LabNative 'docker' @('build', '--platform', 'linux/amd64', '--label',
        'org.opencontainers.image.source=https://github.com/JeanneBM/devops-platform-lab-azure',
        '--tag', $image, (Join-Path $script:LabRoot $app.Context))
    Invoke-LabNative 'docker' @('push', $image)
}
