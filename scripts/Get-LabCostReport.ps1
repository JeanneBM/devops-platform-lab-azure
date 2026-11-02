#Requires -Version 7.2
param([string]$SessionFile = (Join-Path $PSScriptRoot '../.local/session.json'))
$ErrorActionPreference = 'Stop'
$session = Get-Content -LiteralPath $SessionFile -Raw | ConvertFrom-Json
$body = @{
    type = 'ActualCost'; timeframe = 'MonthToDate'
    dataset = @{
        granularity = 'Daily'; aggregation = @{ totalCost = @{ name = 'PreTaxCost'; function = 'Sum' } }
        filter = @{ dimensions = @{ name = 'ResourceGroup'; operator = 'In'; values = @($session.resourceGroup, $session.nodeResourceGroup) } }
        grouping = @(@{ type = 'Dimension'; name = 'ResourceGroup' })
    }
} | ConvertTo-Json -Depth 10
$temp = [IO.Path]::GetTempFileName()
try {
    Set-Content -LiteralPath $temp -Value $body
    & az rest --method post --url "https://management.azure.com/subscriptions/$($session.subscriptionId)/providers/Microsoft.CostManagement/query?api-version=2023-03-01" --body "@$temp" --output json
    if ($LASTEXITCODE -ne 0) { throw 'Cost query failed. Check Cost Management read permissions and billing data availability.' }
} finally { Remove-Item $temp -Force }
Write-Host 'Month-to-date costs for both lab groups. Reporting can lag; empty rows do not prove zero cost.'
