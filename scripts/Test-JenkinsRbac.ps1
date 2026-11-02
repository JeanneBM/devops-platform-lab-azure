#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Kubeconfig)
. (Join-Path $PSScriptRoot 'Common.ps1')
$kube = (Resolve-Path -LiteralPath $Kubeconfig).Path
$controller = 'system:serviceaccount:jenkins:lab-controller'
$agent = 'system:serviceaccount:jenkins-agents:lab-agent'
foreach ($case in @(
    @{ Identity = $controller; Verb = 'create'; Resource = 'pods'; Namespace = 'jenkins-agents'; Allowed = $true },
    @{ Identity = $controller; Verb = 'delete'; Resource = 'deployments'; Namespace = 'python'; Allowed = $false },
    @{ Identity = $controller; Verb = 'get'; Resource = 'secrets'; Namespace = 'default'; Allowed = $false },
    @{ Identity = $agent; Verb = 'create'; Resource = 'pods'; Namespace = 'jenkins-agents'; Allowed = $false },
    @{ Identity = $agent; Verb = 'get'; Resource = 'secrets'; Namespace = 'jenkins'; Allowed = $false }
)) {
    $answer = & kubectl --kubeconfig $kube auth can-i $case.Verb $case.Resource --namespace $case.Namespace --as $case.Identity
    # kubectl returns 1 for an expected denial; only a literal yes/no is accepted.
    $expected = if ($case.Allowed) { 'yes' } else { 'no' }
    if (($answer -join '').Trim() -ne $expected) {
        throw "RBAC mismatch: $($case.Identity) $($case.Verb) $($case.Resource) in $($case.Namespace)."
    }
    Write-Host "RBAC $expected : $($case.Verb) $($case.Resource) in $($case.Namespace) as $($case.Identity)"
}
