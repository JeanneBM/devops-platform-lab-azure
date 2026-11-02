#Requires -Version 7.2
param([Parameter(Mandatory)][string]$Kubeconfig, [switch]$ExerciseAlerts)
. (Join-Path $PSScriptRoot 'PortForward.ps1')
$kube = (Resolve-Path $Kubeconfig).Path
$prom = $null; $loki = $null; $grafana = $null
function Get-PromResult([string]$Query) {
    $url = "$($prom.Base)/api/v1/query?query=$([Uri]::EscapeDataString($Query))"
    return (Invoke-RestMethod $url -TimeoutSec 15).data.result
}
try {
    $prom = Open-LabForward $kube 'observability' 'prometheus' 9090
    $loki = Open-LabForward $kube 'observability' 'loki' 3100
    $grafana = Open-LabForward $kube 'observability' 'grafana' 3000
    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    do {
        $up = @(Get-PromResult 'up{job="applications"} == 1')
        $metrics = @(Get-PromResult 'lab_http_requests_total')
        $state = @(Get-PromResult 'kube_deployment_spec_replicas{namespace="python"}')
        $query = [Uri]::EscapeDataString('{namespace="python"}')
        $logs = Invoke-RestMethod "$($loki.Base)/loki/api/v1/query_range?query=$query&limit=5" -TimeoutSec 15
        if ($up.Count -eq 2 -and $metrics.Count -gt 0 -and $state.Count -gt 0 -and @($logs.data.result).Count -gt 0) { break }
        Start-Sleep -Seconds 5
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($up.Count -ne 2 -or $metrics.Count -eq 0 -or $state.Count -eq 0 -or @($logs.data.result).Count -eq 0) {
        throw 'Metrics, deployment state or collected Python logs are missing.'
    }
    $health = Invoke-RestMethod "$($grafana.Base)/api/health" -TimeoutSec 15
    if ($health.database -ne 'ok') { throw 'Grafana health failed.' }
    $encoded = & kubectl --kubeconfig $kube -n observability get secret grafana-admin -o jsonpath='{.data.password}'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Grafana login secret.' }
    $pass = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
    $cred = [PSCredential]::new('admin', (ConvertTo-SecureString $pass -AsPlainText -Force))
    $dashboard = Invoke-RestMethod "$($grafana.Base)/api/dashboards/uid/azure-devops-lab" -Authentication Basic -Credential $cred -AllowUnencryptedAuthentication -TimeoutSec 15
    if ($dashboard.dashboard.title -ne 'Azure DevOps Lab') { throw 'Provisioned dashboard missing.' }
    if ($ExerciseAlerts) {
        try {
            Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'python', 'scale', 'deployment/pycalculator', '--replicas=0')
            $deadline = [DateTime]::UtcNow.AddMinutes(3)
            do {
                $firing = @(Get-PromResult 'ALERTS{alertname="LabApplicationUnavailable",alertstate="firing"}')
                if ($firing.Count -gt 0) { break }
                Start-Sleep -Seconds 5
            } while ([DateTime]::UtcNow -lt $deadline)
            if ($firing.Count -eq 0) { throw 'Deliberate outage did not trigger the availability alert.' }
        } finally {
            Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'python', 'scale', 'deployment/pycalculator', '--replicas=1')
            Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'python', 'rollout', 'status', 'deployment/pycalculator', '--timeout=180s')
        }
        $deadline = [DateTime]::UtcNow.AddMinutes(2)
        do {
            $firing = @(Get-PromResult 'ALERTS{alertname="LabApplicationUnavailable",alertstate="firing"}')
            if ($firing.Count -eq 0) { break }
            Start-Sleep -Seconds 5
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($firing.Count -gt 0) { throw 'Alert did not resolve after recovery.' }
    }
    Write-Host 'OBSERVABILITY PASSED: both app metrics, Kubernetes state, collected logs, Grafana dashboard and requested alert exercise.'
} finally {
    Close-LabForward $prom; Close-LabForward $loki; Close-LabForward $grafana
}
