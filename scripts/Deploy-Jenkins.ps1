#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Kubeconfig,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$SourceRef,
    [string]$StorageClass = 'managed-csi',
    [string]$ExistingClaim = '',
    [string]$AdminSecretName = ''
)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabTools @('helm', 'kubectl')
Assert-LabHelm
$kube = (Resolve-Path -LiteralPath $Kubeconfig).Path
Invoke-LabNative 'helm' @('upgrade', '--install', 'jenkins-access',
    (Join-Path $script:LabRoot 'charts/jenkins-access'), '--kubeconfig', $kube,
    '--namespace', 'jenkins', '--create-namespace', '--wait', '--timeout', '2m')
Invoke-LabNative 'helm' @('repo', 'add', 'jenkinsci', 'https://charts.jenkins.io', '--force-update')
Invoke-LabNative 'helm' @('repo', 'update', 'jenkinsci')
$current = Get-LabJenkinsValues $kube
if (-not $ExistingClaim -and $current.ContainsKey('persistence') -and $current.persistence.ContainsKey('existingClaim')) { $ExistingClaim = $current.persistence.existingClaim }
if (-not $AdminSecretName) { $AdminSecretName = Get-LabJenkinsAdminSecret $kube }
$extra = @()
if ($ExistingClaim) { $extra += @('--set-string', "persistence.existingClaim=$ExistingClaim") }
if ($AdminSecretName -and $AdminSecretName -ne 'jenkins') { $extra += @('--set-string', "controller.admin.existingSecret=$AdminSecretName", '--set', 'controller.admin.createSecret=false') }
$chartVersion = '5.10.9'
$downloadDir = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString()))
$chartPath = Join-Path $downloadDir.FullName "jenkins-$chartVersion.tgz"
try {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-LabNative 'helm' @('pull', 'jenkinsci/jenkins', '--version', $chartVersion,
                '--destination', $downloadDir.FullName)
            break
        }
        catch {
            if ($attempt -eq 3) { throw }
            if (Test-Path -LiteralPath $chartPath) { Remove-Item -LiteralPath $chartPath }
            Write-Warning "Jenkins Helm chart download failed (attempt $attempt of 3). Retrying."
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
    Invoke-LabNative 'helm' (@('upgrade', '--install', 'jenkins', $chartPath,
        '--kubeconfig', $kube, '--namespace', 'jenkins',
        '--values', (Join-Path $script:LabRoot 'helm-values/jenkins.yaml'),
        '--set-string', "controller.containerEnv[0].value=$SourceRef",
        '--set-string', "persistence.storageClass=$StorageClass",
        '--set-file', "controller.initScripts.lab-job=$(Join-Path $script:LabRoot 'jenkins/init-job.groovy')",
        '--atomic', '--wait', '--timeout', '15m', '--history-max', '5') + $extra)
}
finally {
    Remove-Item -LiteralPath $downloadDir.FullName -Recurse -Force
}
Write-Host 'Jenkins installed. No automatic job trigger on startup; run Test-Jenkins.ps1 explicitly.'
