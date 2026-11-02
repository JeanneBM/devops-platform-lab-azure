#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Kubeconfig,
    [Parameter(Mandatory)][string]$BackupFolder,
    [Parameter(Mandatory)][string]$KeyFile,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$SourceRef,
    [string]$StorageClass = 'managed-csi'
)
. (Join-Path $PSScriptRoot 'JenkinsStorage.ps1')
$kube = (Resolve-Path $Kubeconfig).Path
$folder = (Resolve-Path $BackupFolder).Path
$key = (Resolve-Path $KeyFile).Path
$manifest = Get-Content (Join-Path $folder 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1) { throw 'Unsupported backup schema.' }
foreach ($check in @(
    @{ Path = (Join-Path $folder 'home.tgz'); Hash = $manifest.homeSha256 },
    @{ Path = (Join-Path $folder 'admin-secret.json'); Hash = $manifest.adminSha256 },
    @{ Path = $key; Hash = $manifest.keySha256 }
)) {
    if ((Get-FileHash $check.Path).Hash -ne $check.Hash) { throw "Backup checksum mismatch: $($check.Path)" }
}
$state = Get-JenkinsState $kube
if ($state.Image -ne $manifest.image) { throw 'Restore requires the same Jenkins image as the backup. Upgrade separately.' }
$suffix = [guid]::NewGuid().ToString('N').Substring(0,8)
$pvc = "jenkins-restored-$suffix"
$adminName = "jenkins-restored-admin-$suffix"
$claim = @{ apiVersion = 'v1'; kind = 'PersistentVolumeClaim'; metadata = @{ name = $pvc; namespace = 'jenkins' }; spec = @{
    accessModes = @('ReadWriteOnce'); storageClassName = $StorageClass; resources = @{ requests = @{ storage = '10Gi' } }
} }
$claim | ConvertTo-Json -Depth 10 | & kubectl --kubeconfig $kube create -f - | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Cannot create a new restore PVC.' }
$stopped = $false
try {
    Stop-JenkinsForStorage $kube
    $stopped = $true
    New-JenkinsMaintenance $kube $pvc
    Push-Location $folder
    try { Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, 'cp', 'home.tgz', 'jenkins/jenkins-maintenance:/tmp/home.tgz') }
    finally { Pop-Location }
    Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'jenkins', 'exec', 'jenkins-maintenance', '--', 'tar', 'xzf', '/tmp/home.tgz', '-C', '/data')
    Push-Location (Split-Path $key -Parent)
    try { Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, 'cp', (Split-Path $key -Leaf), 'jenkins/jenkins-maintenance:/data/secrets/master.key') }
    finally { Pop-Location }
    $secret = Get-Content (Join-Path $folder 'admin-secret.json') -Raw | ConvertFrom-Json
    $secret.metadata.name = $adminName
    $secret | ConvertTo-Json -Depth 10 | & kubectl --kubeconfig $kube create -f - | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Cannot restore administrator secret.' }
    Remove-JenkinsMaintenance $kube
    & (Join-Path $PSScriptRoot 'Deploy-Jenkins.ps1') -Kubeconfig $kube -SourceRef $SourceRef `
        -StorageClass $StorageClass -ExistingClaim $pvc -AdminSecretName $adminName
    $stopped = $false
} finally {
    if ($stopped) {
        Remove-JenkinsMaintenance $kube
        Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'jenkins', 'scale', 'statefulset/jenkins', '--replicas=1')
    }
}
Write-Host "Restored to new PVC $pvc. Original PVC $($state.Pvc) was not overwritten."
return @{ Pvc = $pvc; AdminSecretName = $adminName }
