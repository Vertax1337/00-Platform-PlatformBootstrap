[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OrganizationUrl
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"

$session = Initialize-BSSEAzureDevOpsSession -OrganizationUrl $OrganizationUrl

Write-Host ""
Write-Host "Alle automatisch prüfbaren Voraussetzungen sind erfüllt." -ForegroundColor Green
Write-Host "Azure DevOps: $($session.OrganizationUrl)"
