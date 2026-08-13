[CmdletBinding()]
param(
    [string]$OrganizationUrl = 'https://dev.azure.com/BSSE-CloudOps/',
    [string]$Project = '00-Platform',
    [string]$Repository = 'PlatformBootstrap',
    [string]$PipelineName = 'Customer-Onboarding-TEST-SystemAccessToken',
    [string]$YamlPath = 'pipelines/customer-onboarding-system-access-token-test.yml',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"

if (Test-BSSEPipelineContext) {
    throw 'Diese temporäre Test-Pipeline-Registrierung darf nur lokal durch einen Administrator ausgeführt werden.'
}

$session = Initialize-BSSEAzureDevOpsSession -OrganizationUrl $OrganizationUrl
$OrganizationUrl = $session.OrganizationUrl

Write-Host ''
Write-Host 'BSSE Customer-Onboarding System.AccessToken TEST Pipeline Registration' -ForegroundColor Cyan
Write-Host "Organization: $OrganizationUrl"
Write-Host "Project:      $Project"
Write-Host "Repository:   $Repository"
Write-Host "Pipeline:     $PipelineName"
Write-Host "YAML:         $YamlPath"
Write-Host "Mode:         $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"
Write-Host ''
Write-Host '[TEMPORARY] Diese Pipeline ist ausschließlich der E2E-Validierung während des WIF-Preview-BLOCKED-Status gewidmet.' -ForegroundColor Yellow
Write-Host '            Produktiver Zielzustand bleibt Customer-Onboarding + sc-platform-bootstrap-azdo (WIF).' -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-BSSEProjectExists -OrganizationUrl $OrganizationUrl -Project $Project)) {
    throw "Azure-DevOps-Projekt '$Project' existiert nicht."
}

$repos = @(Get-BSSEProjectRepositories -OrganizationUrl $OrganizationUrl -Project $Project)
$repo = $repos | Where-Object { $_.name -eq $Repository } | Select-Object -First 1
if (-not $repo) {
    throw "Repository '$Project/$Repository' existiert nicht."
}
Write-Host "[OK] Repository $Project/$Repository vorhanden." -ForegroundColor Green

$pipelinesJson = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'pipelines','list',
    '--org',$OrganizationUrl,
    '--project',$Project,
    '--output','json',
    '--only-show-errors'
)
$pipelines = @($pipelinesJson | ConvertFrom-Json)
$matches = @($pipelines | Where-Object { $_.name -eq $PipelineName })

if ($matches.Count -gt 1) {
    throw "Mehrere Pipelines heißen exakt '$PipelineName'."
}

if ($matches.Count -eq 1) {
    Write-Host "[EXISTS] Pipeline $PipelineName" -ForegroundColor DarkGray
    Write-Host "         Pipeline ID: $($matches[0].id)" -ForegroundColor DarkGray
    return
}

if (-not $Apply) {
    Write-Host "[PLAN] Register temporary test pipeline $PipelineName" -ForegroundColor Yellow
    Write-Host "       Source: $Project/$Repository/$YamlPath" -ForegroundColor DarkGray
    Write-Host '       First run will NOT be started automatically.' -ForegroundColor DarkGray
    return
}

Write-Host "[CREATE] Pipeline $PipelineName" -ForegroundColor Green
Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'pipelines','create',
    '--org',$OrganizationUrl,
    '--project',$Project,
    '--name',$PipelineName,
    '--repository',$Repository,
    '--repository-type','tfsgit',
    '--branch','main',
    '--yml-path',$YamlPath,
    '--skip-first-run','true',
    '--only-show-errors'
) | Out-Null

$pipelinesJson = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'pipelines','list',
    '--org',$OrganizationUrl,
    '--project',$Project,
    '--output','json',
    '--only-show-errors'
)
$pipelines = @($pipelinesJson | ConvertFrom-Json)
$created = @($pipelines | Where-Object { $_.name -eq $PipelineName })

if ($created.Count -ne 1) {
    throw "Pipeline '$PipelineName' wurde nach der Erstellung nicht eindeutig wiedergefunden."
}

Write-Host "[OK] Temporäre Test-Pipeline $PipelineName registriert." -ForegroundColor Green
Write-Host "     Pipeline ID: $($created[0].id)" -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Nächster Schritt:' -ForegroundColor Cyan
Write-Host "- Pipeline '$PipelineName' manuell über Run pipeline starten." -ForegroundColor DarkGray
Write-Host '- confirmTemporarySystemAccessToken = true setzen.' -ForegroundColor DarkGray
Write-Host '- Validate gibt die tatsächlich verwendete Build-Service-Identität aus.' -ForegroundColor DarkGray
Write-Host '- Dry Run prüfen. Approval erst nach Permission-Review freigeben.' -ForegroundColor DarkGray
