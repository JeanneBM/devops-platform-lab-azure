. (Join-Path $PSScriptRoot 'Common.ps1')
function Open-LabForward {
    param([string]$Kube, [string]$Namespace, [string]$Service, [int]$Port)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = (Get-Command kubectl).Source
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    foreach ($arg in @('--kubeconfig', $Kube, '-n', $Namespace, 'port-forward', "service/$Service", ":$Port", '--address=127.0.0.1')) {
        $process.StartInfo.ArgumentList.Add($arg)
    }
    try {
        [void]$process.Start()
        $stderr = $process.StandardError.ReadToEndAsync()
        $line = $process.StandardOutput.ReadLineAsync()
        if (-not $line.Wait(30000) -or $line.Result -notmatch '127\.0\.0\.1:(\d+)') { throw "Cannot forward $Service." }
        return @{ Process = $process; Base = "http://127.0.0.1:$($Matches[1])"; Errors = $stderr }
    } catch {
        if (-not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
        throw
    }
}
function Close-LabForward {
    param($Forward)
    if ($Forward) {
        if (-not $Forward.Process.HasExited) { $Forward.Process.Kill($true); $Forward.Process.WaitForExit() }
        $Forward.Process.Dispose()
    }
}
