#Requires -Version 7.2
param([string]$Location = 'polandcentral', [string]$NodeSize = 'Standard_D4as_v5', [ValidateRange(1,720)][int]$Hours = 6)
$ErrorActionPreference = 'Stop'
if ($Location -notmatch '^[a-z0-9]+$' -or $NodeSize -notmatch '^Standard_[A-Za-z0-9_]+$') { throw 'Invalid region or SKU.' }
$filter = "serviceName eq 'Virtual Machines' and armRegionName eq '$Location' and armSkuName eq '$NodeSize' and priceType eq 'Consumption'"
$url = 'https://prices.azure.com/api/retail/prices?currencyCode=USD&$filter=' + [Uri]::EscapeDataString($filter)
$items = @()
do {
    $page = Invoke-RestMethod $url -TimeoutSec 30
    $items += $page.Items
    $url = $page.NextPageLink
} while ($url)
$rates = @($items | Where-Object {
    $_.isPrimaryMeterRegion -eq $true -and $_.unitOfMeasure -eq '1 Hour' -and $_.productName -like 'Virtual Machines*' -and $_.productName -notmatch 'Windows' -and
    $_.skuName -notmatch 'Spot|Low Priority' -and $_.meterName -notmatch 'Spot|Low Priority' -and $_.retailPrice -gt 0
} | Select-Object -ExpandProperty retailPrice -Unique)
if ($rates.Count -ne 1) { throw 'Cannot identify one unambiguous Linux PAYG retail rate. Review Azure Pricing Calculator before apply.' }
$compute = [double]$rates[0] * 2 * $Hours
# Explicit planning allowance, not a fetched rate for disks, registry, LB, IP and small transfer.
$allowance = 0.15 * $Hours
[pscustomobject]@{
    Region = $Location; NodeSku = $NodeSize; Nodes = 2; Hours = $Hours; Currency = 'USD'
    RetailVmHourlyPerNode = $rates[0]; EstimatedCompute = [math]::Round($compute,2)
    OtherServicesPlanningAllowance = [math]::Round($allowance,2)
    PlanningTotal = [math]::Round($compute + $allowance,2)
    Limitation = 'Retail VM compute only is live-priced. Other meters are allowances; taxes, offers, quota, availability and large transfer excluded. Not a spending cap.'
}
