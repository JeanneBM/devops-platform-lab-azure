#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Kubeconfig, [string]$AdminSecretName = 'jenkins')
. (Join-Path $PSScriptRoot 'Common.ps1')
$kube = (Resolve-Path -LiteralPath $Kubeconfig).Path
& (Join-Path $PSScriptRoot 'Test-JenkinsRbac.ps1') -Kubeconfig $kube
$secretJson = & kubectl --kubeconfig $kube -n jenkins get secret $AdminSecretName -o json
if ($LASTEXITCODE -ne 0) { throw 'Cannot retrieve the local Jenkins administrator secret.' }
$secret = ($secretJson -join "`n") | ConvertFrom-Json
$username = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.'jenkins-admin-user'))
$password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.'jenkins-admin-password'))
$credential = [PSCredential]::new($username, (ConvertTo-SecureString $password -AsPlainText -Force))
$password = $null
$secretJson = $null
$secret = $null
$process = [Diagnostics.Process]::new()
$process.StartInfo.FileName = (Get-Command kubectl).Source
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
foreach ($arg in @('--kubeconfig', $kube, '-n', 'jenkins', 'port-forward', 'service/jenkins', ':8080', '--address=127.0.0.1')) {
    $process.StartInfo.ArgumentList.Add($arg)
}
try {
    [void]$process.Start()
    $stderr = $process.StandardError.ReadToEndAsync()
    $lineTask = $process.StandardOutput.ReadLineAsync()
    if (-not $lineTask.Wait(30000)) { throw 'Jenkins port-forward timed out.' }
    if ($lineTask.Result -notmatch '127\.0\.0\.1:(\d+)') { throw 'Jenkins port-forward failed.' }
    $base = "http://127.0.0.1:$($Matches[1])"
    $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $request = @{
        Credential = $credential; Authentication = 'Basic'; AllowUnencryptedAuthentication = $true
        WebSession = $session; TimeoutSec = 20
    }
    # Basic authentication is used only over the explicit loopback port-forward.
    $info = Invoke-RestMethod "$base/api/json?tree=numExecutors" @request
    if ($info.numExecutors -ne 0) { throw 'Controller executors must be zero.' }
    $pluginInfo = Invoke-RestMethod "$base/pluginManager/api/json?tree=plugins[shortName,version,active]" @request
    foreach ($name in @('kubernetes', 'workflow-aggregator', 'git', 'configuration-as-code')) {
        $plugin = @($pluginInfo.plugins | Where-Object { $_.shortName -eq $name })
        if ($plugin.Count -ne 1 -or -not $plugin[0].active) { throw "Required plugin inactive: $name" }
        Write-Host "Active plugin: $name $($plugin[0].version)"
    }
    $inactive = @($pluginInfo.plugins | Where-Object { -not $_.active })
    if ($inactive.Count -gt 0) { throw 'Installed Jenkins plugins failed to activate. Inspect controller startup logs.' }
    $job = Invoke-RestMethod "$base/job/lab-verify/api/json?tree=nextBuildNumber" @request
    $number = $job.nextBuildNumber
    $crumb = Invoke-RestMethod "$base/crumbIssuer/api/json" @request
    $headers = @{}
    $headers[$crumb.crumbRequestField] = $crumb.crumb
    Invoke-RestMethod "$base/job/lab-verify/buildWithParameters?delay=0sec" -Method Post -ContentType 'application/x-www-form-urlencoded' -Body '' -Headers $headers @request | Out-Null
    $observedAgent = $false
    $completed = $false
    $deadline = [DateTime]::UtcNow.AddMinutes(12)
    while ([DateTime]::UtcNow -lt $deadline) {
        $podJson = & kubectl --kubeconfig $kube -n jenkins-agents get pods -l app.kubernetes.io/component=lab-build-agent -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot observe dynamic agents.' }
        $pods = ($podJson -join "`n") | ConvertFrom-Json
        foreach ($pod in $pods.items) {
            if ($pod.spec.serviceAccountName -ne 'lab-agent' -or $pod.spec.automountServiceAccountToken -ne $false) {
                throw 'Agent identity/token configuration is incorrect.'
            }
            $observedAgent = $true
        }
        try {
            $build = Invoke-RestMethod "$base/job/lab-verify/$number/api/json?tree=building,result" @request
        } catch {
            if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
            Start-Sleep -Seconds 3
            continue
        }
        if (-not $build.building) {
            if ($build.result -ne 'SUCCESS') {
                # Console output is build output only; no admin credentials are printed.
                $console = Invoke-RestMethod "$base/job/lab-verify/$number/consoleText" @request
                Write-Host $console
                throw "Jenkins build $number ended with $($build.result)."
            }
            $console = Invoke-RestMethod "$base/job/lab-verify/$number/consoleText" @request
            foreach ($marker in @('LAB_SHARED_LIBRARY_LOADED', 'LAB_AGENT_HOST=', 'LAB_DYNAMIC_AGENT_TESTS_PASSED')) {
                if ($console -notmatch [regex]::Escape($marker)) { throw "Missing pipeline evidence: $marker" }
            }
            $completed = $true
            break
        }
        Start-Sleep -Seconds 3
    }
    if (-not $completed -or -not $observedAgent) { throw 'No successful build with an observed dynamic agent.' }
    $deadline = [DateTime]::UtcNow.AddMinutes(1)
    do {
        $podJson = & kubectl --kubeconfig $kube -n jenkins-agents get pods -l app.kubernetes.io/component=lab-build-agent -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot verify agent cleanup.' }
        $pods = ($podJson -join "`n") | ConvertFrom-Json
        if (@($pods.items).Count -eq 0) { break }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    if (@($pods.items).Count -ne 0) { throw 'Agent pods were not removed after the build.' }
    Write-Host "Jenkins build ${number}: shared library loaded, Python/Java tests passed on a dynamic agent, agent removed, RBAC checks passed."
} finally {
    try {
        if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    } catch { Write-Warning 'Check for remaining Jenkins port-forward processes.' }
    $process.Dispose()
    $credential = $null
}
