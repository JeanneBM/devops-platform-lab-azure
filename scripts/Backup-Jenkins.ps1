#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Kubeconfig,
    [string]$BackupDirectory = (Join-Path $PSScriptRoot '../.backups'),
    [string]$KeyDirectory = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.devops-lab-keys'),
    [string]$AdminSecretName = ''
)
. (Join-Path $PSScriptRoot 'JenkinsStorage.ps1')
$kube = (Resolve-Path $Kubeconfig).Path
if (-not $AdminSecretName) { $AdminSecretName = Get-LabJenkinsAdminSecret $kube }
$state = Get-JenkinsState $kube
if ($state.Replicas -ne 1) { throw 'Backup expects a running single controller.' }
$id = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$folder = Join-Path $BackupDirectory $id
New-Item -ItemType Directory -Force $folder, $KeyDirectory | Out-Null
$folder = (Resolve-Path $folder).Path
$key = Join-Path ((Resolve-Path $KeyDirectory).Path) "$id.key"
$raw = & kubectl --kubeconfig $kube -n jenkins get secret $AdminSecretName -o json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read Jenkins administrator secret.' }
$secret = ($raw -join "`n") | ConvertFrom-Json
@{ apiVersion = 'v1'; kind = 'Secret'; type = 'Opaque'; metadata = @{ name = 'jenkins'; namespace = 'jenkins' }; data = $secret.data } |
    ConvertTo-Json -Depth 10 | Set-Content (Join-Path $folder 'admin-secret.json')
Protect-LabFile (Join-Path $folder 'admin-secret.json')
$stopped = $false
try {
    Stop-JenkinsForStorage $kube
    $stopped = $true
    New-JenkinsMaintenance $kube $state.Pvc
    Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'jenkins', 'exec', 'jenkins-maintenance', '--',
        'tar', 'czf', '/tmp/home.tgz', '--exclude=./secrets/master.key', '-C', '/data', '.')
    Push-Location $folder
    try {
        Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, 'cp', 'jenkins/jenkins-maintenance:/tmp/home.tgz', 'home.tgz')
    } finally { Pop-Location }
    # A relative local destination avoids kubectl's Windows drive-letter/remote-path ambiguity.
    Push-Location (Split-Path $key -Parent)
    try {
        Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, 'cp', 'jenkins/jenkins-maintenance:/data/secrets/master.key', (Split-Path $key -Leaf))
    } finally { Pop-Location }
    Protect-LabFile $key
    Protect-LabFile (Join-Path $folder 'home.tgz')
    @{
        schema = 1; id = $id; image = $state.Image; sourcePvc = $state.Pvc
        homeSha256 = (Get-FileHash (Join-Path $folder 'home.tgz')).Hash
        adminSha256 = (Get-FileHash (Join-Path $folder 'admin-secret.json')).Hash
        keySha256 = (Get-FileHash $key).Hash
    } | ConvertTo-Json | Set-Content (Join-Path $folder 'manifest.json')
    Write-Host "Backup complete: $folder. Controller key stored separately: $key"
} finally {
    if ($stopped) {
        Remove-JenkinsMaintenance $kube
        Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'jenkins', 'scale', 'statefulset/jenkins', '--replicas=1')
        Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'jenkins', 'rollout', 'status', 'statefulset/jenkins', '--timeout=600s')
    }
}
return $folder
