#Requires -Version 7.2
param([Parameter(Mandatory)][string]$Kubeconfig)
. (Join-Path $PSScriptRoot 'Common.ps1')
$kube = (Resolve-Path $Kubeconfig).Path
Assert-LabHelm
Invoke-LabNative 'helm' @('upgrade', '--install', 'observability', (Join-Path $script:LabRoot 'charts/observability'),
    '--kubeconfig', $kube, '--namespace', 'observability', '--create-namespace', '--atomic', '--wait', '--timeout', '8m', '--history-max', '3')
