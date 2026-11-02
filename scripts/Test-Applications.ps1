#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Kubeconfig)
. (Join-Path $PSScriptRoot 'Common.ps1')
$kube = (Resolve-Path -LiteralPath $Kubeconfig).Path
Assert-LabTools @('kubectl')
foreach ($app in @(
    @{ Name = 'pycalculator'; Namespace = 'python' },
    @{ Name = 'g4g7singleton'; Namespace = 'java' }
)) {
    Invoke-LabNative 'kubectl' @('--kubeconfig', $kube, '-n', $app.Namespace,
        'rollout', 'status', "deployment/$($app.Name)", '--timeout=180s')
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = (Get-Command kubectl).Source
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    # Ask kubectl to allocate a free loopback port. Never bind to 0.0.0.0.
    foreach ($arg in @('--kubeconfig', $kube, '-n', $app.Namespace, 'port-forward',
        "service/$($app.Name)", ':80', '--address=127.0.0.1')) {
        $process.StartInfo.ArgumentList.Add($arg)
    }
    try {
        [void]$process.Start()
        $stderr = $process.StandardError.ReadToEndAsync()
        $lineTask = $process.StandardOutput.ReadLineAsync()
        if (-not $lineTask.Wait(30000)) { throw "Port forward timed out for $($app.Name)." }
        $line = $lineTask.Result
        if ($line -notmatch '127\.0\.0\.1:(\d+)') {
            throw "Port forward failed for $($app.Name): $line"
        }
        $base = "http://127.0.0.1:$($Matches[1])"
        $health = Invoke-WebRequest "$base/healthz" -TimeoutSec 10
        if ($health.StatusCode -ne 200) { throw 'Health check failed.' }
        if ($app.Namespace -eq 'python') {
            $response = Invoke-WebRequest "$base/calculations" -Method Post -Body @{
                x = '2'; y = '3'; operation = 'addition'
            } -TimeoutSec 10
            if ($response.Content -notmatch '5\.0') { throw 'Calculator result is incorrect.' }
            $bad = Invoke-WebRequest "$base/calculations" -Method Post -Body @{
                x = '2'; y = '0'; operation = 'division'
            } -SkipHttpErrorCheck -TimeoutSec 10
            if ($bad.StatusCode -ne 400) { throw 'Division by zero was not rejected.' }
        } else {
            $response = Invoke-WebRequest "$base/" -TimeoutSec 10
            foreach ($greeting in @('Czesc!', 'Guten Tag!', 'Hola!')) {
                if ($response.Content -notmatch $greeting) { throw "Missing greeting: $greeting" }
            }
        }
        Write-Host "$($app.Name): health and behavior checks passed."
    } finally {
        try {
            if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        } catch { Write-Warning 'Check for a remaining kubectl port-forward process.' }
        $process.Dispose()
    }
}
