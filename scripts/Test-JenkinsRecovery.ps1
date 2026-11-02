#Requires -Version 7.2
param([Parameter(Mandatory)][string]$Kubeconfig, [Parameter(Mandatory)][string]$SourceRef, [string]$StorageClass = 'standard')
. (Join-Path $PSScriptRoot 'Common.ps1')
$kube = (Resolve-Path $Kubeconfig).Path
$temp = Join-Path ([IO.Path]::GetTempPath()) ('jenkins-recovery-' + [guid]::NewGuid().ToString('N'))
try {
    Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'jenkins', 'exec', 'jenkins-0', '-c', 'jenkins', '--', 'sh', '-c', 'echo recovery-proof > /var/jenkins_home/recovery-marker')
    $backup = & (Join-Path $PSScriptRoot 'Backup-Jenkins.ps1') -Kubeconfig $kube -BackupDirectory (Join-Path $temp 'backups') -KeyDirectory (Join-Path $temp 'keys')
    $key = @(Get-ChildItem (Join-Path $temp 'keys') -Filter '*.key')[0].FullName
    $manifestPath = Join-Path $backup 'manifest.json'
    $originalManifest = Get-Content $manifestPath -Raw
    $badManifest = $originalManifest | ConvertFrom-Json
    $badManifest.homeSha256 = '0' * 64
    $badManifest | ConvertTo-Json | Set-Content $manifestPath
    $rejected = $false
    try {
        & (Join-Path $PSScriptRoot 'Restore-Jenkins.ps1') -Kubeconfig $kube -BackupFolder $backup -KeyFile $key -SourceRef $SourceRef -StorageClass $StorageClass | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'checksum mismatch') { throw }
        $rejected = $true
    } finally { Set-Content $manifestPath $originalManifest }
    if (-not $rejected) { throw 'Corrupted backup was accepted.' }
    $restored = & (Join-Path $PSScriptRoot 'Restore-Jenkins.ps1') -Kubeconfig $kube -BackupFolder $backup -KeyFile $key -SourceRef $SourceRef -StorageClass $StorageClass
    Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'jenkins', 'exec', 'jenkins-0', '-c', 'jenkins', '--', 'test', '-f', '/var/jenkins_home/recovery-marker')
    Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', 'jenkins', 'exec', 'jenkins-0', '-c', 'jenkins', '--', 'test', '-f', '/var/jenkins_home/jobs/lab-verify/builds/1/build.xml')
    & (Join-Path $PSScriptRoot 'Test-Jenkins.ps1') -Kubeconfig $kube -AdminSecretName $restored.AdminSecretName
    Write-Host 'RECOVERY PASSED: new PVC, restored marker and build history, successful new dynamic-agent build.'
} finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
