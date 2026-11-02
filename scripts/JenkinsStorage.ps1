. (Join-Path $PSScriptRoot 'Common.ps1')

function Get-JenkinsState {
    param([string]$Kube)
    $raw = & kubectl --kubeconfig $Kube -n jenkins get statefulset jenkins -o json
    if ($LASTEXITCODE -ne 0) { throw 'Jenkins StatefulSet is missing.' }
    $state = ($raw -join "`n") | ConvertFrom-Json
    $volume = @($state.spec.template.spec.volumes | Where-Object { $_.PSObject.Properties.Name -contains 'persistentVolumeClaim' })
    if ($volume.Count -ne 1) { throw 'Expected exactly one Jenkins home PVC.' }
    $container = @($state.spec.template.spec.containers | Where-Object name -eq jenkins)[0]
    return @{ Pvc = $volume[0].persistentVolumeClaim.claimName; Image = $container.image; Replicas = $state.spec.replicas }
}

function Stop-JenkinsForStorage {
    param([string]$Kube)
    $raw = & kubectl --kubeconfig $Kube -n jenkins-agents get pods -o json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot check active agents.' }
    if (@((($raw -join "`n") | ConvertFrom-Json).items).Count -gt 0) {
        throw 'Build agents are active. Wait for builds to finish before offline storage work.'
    }
    Invoke-LabNative 'kubectl' @('--kubeconfig', $Kube, '-n', 'jenkins', 'scale', 'statefulset/jenkins', '--replicas=0')
    Invoke-LabNative 'kubectl' @('--kubeconfig', $Kube, '-n', 'jenkins', 'wait', '--for=delete', 'pod/jenkins-0', '--timeout=180s')
}

function New-JenkinsMaintenance {
    param([string]$Kube, [string]$Pvc)
    $pod = @{
        apiVersion = 'v1'; kind = 'Pod'; metadata = @{ name = 'jenkins-maintenance'; namespace = 'jenkins' }
        spec = @{
            restartPolicy = 'Never'; automountServiceAccountToken = $false
            securityContext = @{ runAsUser = 1000; runAsGroup = 1000; fsGroup = 1000; runAsNonRoot = $true }
            containers = @(@{
                name = 'maintenance'; image = 'busybox:1.37.0'; command = @('sleep', '3600')
                securityContext = @{ allowPrivilegeEscalation = $false; capabilities = @{ drop = @('ALL') } }
                resources = @{ requests = @{ cpu = '50m'; memory = '64Mi' }; limits = @{ cpu = '250m'; memory = '128Mi' } }
                volumeMounts = @(@{ name = 'home'; mountPath = '/data' })
            })
            volumes = @(@{ name = 'home'; persistentVolumeClaim = @{ claimName = $Pvc } })
        }
    }
    $pod | ConvertTo-Json -Depth 20 | & kubectl --kubeconfig $Kube create -f - | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create maintenance pod; another storage operation may be running.' }
    Invoke-LabNative 'kubectl' @('--kubeconfig', $Kube, '-n', 'jenkins', 'wait', '--for=condition=Ready', 'pod/jenkins-maintenance', '--timeout=180s')
}

function Remove-JenkinsMaintenance {
    param([string]$Kube)
    Invoke-LabNative 'kubectl' @('--kubeconfig', $Kube, '-n', 'jenkins', 'delete', 'pod/jenkins-maintenance', '--ignore-not-found', '--wait=true', '--timeout=120s')
}

function Protect-LabFile {
    param([string]$Path)
    if (-not [OperatingSystem]::IsWindows()) {
        [IO.File]::SetUnixFileMode($Path, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite)
    }
}
