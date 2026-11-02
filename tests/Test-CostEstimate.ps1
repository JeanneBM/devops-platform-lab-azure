#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
function global:Invoke-RestMethod {
    param($Uri, $TimeoutSec)
    return @{ Items = @(
        @{ unitOfMeasure = '1 Hour'; productName = 'Linux'; skuName = 'D4as v5'; meterName = 'D4as v5'; retailPrice = 0.2; isPrimaryMeterRegion = $true },
        @{ unitOfMeasure = '1 Hour'; productName = 'Windows'; skuName = 'D4as v5'; meterName = 'D4as v5'; retailPrice = 0.4; isPrimaryMeterRegion = $true },
        @{ unitOfMeasure = '1 Hour'; productName = 'Linux'; skuName = 'D4as v5 Spot'; meterName = 'D4as v5 Spot'; retailPrice = 0.01; isPrimaryMeterRegion = $true }
    ); NextPageLink = '' }
}
try {
    $result = & (Join-Path $root 'scripts/Get-LabCostEstimate.ps1') -Hours 6
    if ($result.EstimatedCompute -ne 2.4 -or $result.PlanningTotal -ne 3.3) { throw 'Wrong price filtering or node/hour arithmetic.' }
    Write-Host 'Cost estimator contract passed with synthetic prices; no network calls.'
} finally { Remove-Item function:Invoke-RestMethod }
