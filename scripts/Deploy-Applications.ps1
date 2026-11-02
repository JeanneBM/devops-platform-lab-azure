#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Registry,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')][string]$ImageTag,
    [Parameter(Mandatory)][string]$Kubeconfig
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$kube = (Resolve-Path -LiteralPath $Kubeconfig).Path
Assert-LabTools @('helm', 'kubectl')
Assert-LabHelm
Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, 'cluster-info')
$chart = Join-Path $script:LabRoot 'charts/lab-app'
foreach ($app in @(
    @{ Name = 'pycalculator'; Namespace = 'python' },
    @{ Name = 'g4g7singleton'; Namespace = 'java' }
)) {
    $values = Join-Path $script:LabRoot "helm-values/$($app.Namespace).yaml"
    Invoke-LabNative 'helm' @('upgrade', '--install', $app.Name, $chart,
        '--kubeconfig', $kube, '--namespace', $app.Namespace, '--create-namespace',
        '--values', $values, '--set-string', "image.repository=$Registry/$($app.Name)",
        '--set-string', "image.tag=$ImageTag", '--atomic', '--wait', '--timeout', '5m', '--history-max', '5')
}
