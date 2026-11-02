#Requires -Version 7.2
param([string]$Kubeconfig = (Join-Path $PSScriptRoot '../.local/aks.kubeconfig'), [switch]$ExerciseAlerts)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Test-Applications.ps1') -Kubeconfig $Kubeconfig
& (Join-Path $PSScriptRoot 'Test-Jenkins.ps1') -Kubeconfig $Kubeconfig
& (Join-Path $PSScriptRoot 'Test-Observability.ps1') -Kubeconfig $Kubeconfig -ExerciseAlerts:$ExerciseAlerts
