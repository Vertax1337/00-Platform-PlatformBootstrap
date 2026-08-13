[CmdletBinding()]
param(
    [string]$OrganizationUrl = 'https://dev.azure.com/BSSE-CloudOps/',
    [string]$Project = '00-Platform',
    [string]$Repository = 'PlatformBootstrap',
    [string]$PipelineName = 'Customer-Onboarding-TEST-AzureRmWifBridge',
    [string]$YamlPath = 'pipelines/customer-onboarding-azure-rm-wif-bridge-test.yml',
    [string]$ServiceConnectionName = 'sc-platform-bootstrap-azdo-arm-bridge',
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
Write-Host 'BSSE Customer-Onboarding AzureRM-WIF Bridge TEST Pipeline Registration' -ForegroundColor Cyan
Write-Host "Organization:       $OrganizationUrl"
Write-Host "Project:            $Project"
Write-Host "Repository:         $Repository"
Write-Host "Pipeline:           $PipelineName"
Write-Host "YAML:               $YamlPath"
Write-Host "Service Connection: $ServiceConnectionName"
Write-Host "Mode:               $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"
Write-Host ''
Write-Host '[TEMPORARY] Productive target remains Customer-Onboarding + sc-platform-bootstrap-azdo (workloadidentityuser WIF).' -ForegroundColor Yellow
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

$endpointsResult = Invoke-BSSEAz -Arguments @(
    'devops','service-endpoint','list',
    '--org',$OrganizationUrl,
    '--project',$Project,
    '--output','json',
    '--only-show-errors'
)
if ($endpointsResult.ExitCode -ne 0) {
    throw "Service Connections konnten nicht gelesen werden.`n$($endpointsResult.Output)"
}

$endpointMatches = @(@($endpointsResult.Output | ConvertFrom-Json) | Where-Object {
    $_.name -eq $ServiceConnectionName
})

if ($endpointMatches.Count -gt 1) {
    throw "Mehrere Service Connections heißen exakt '$ServiceConnectionName'."
}

if ($endpointMatches.Count -eq 0) {
    Write-Host "[BLOCKED] Temporäre Bridge-Service-Connection '$ServiceConnectionName' fehlt." -ForegroundColor Red
    Write-Host '          Erzeuge und verifiziere zuerst die AzureRM-WIF-Bridge samt eigenem FIC.' -ForegroundColor DarkGray
    if ($Apply) {
        throw "Bridge-Service-Connection '$ServiceConnectionName' fehlt."
    }
    return
}

Write-Host "[OK] Bridge-Service-Connection $ServiceConnectionName vorhanden." -ForegroundColor Green

$pipelinesResult = Invoke-BSSEAz -Arguments @(
    'pipelines','list',
    '--org',$OrganizationUrl,
    '--project',$Project,
    '--output','json',
    '--only-show-errors'
)
if ($pipelinesResult.ExitCode -ne 0) {
    throw "Pipelines konnten nicht gelesen werden.`n$($pipelinesResult.Output)"
}

$matches = @(@($pipelinesResult.Output | ConvertFrom-Json) | Where-Object { $_.name -eq $PipelineName })
if ($matches.Count -gt 1) {
    throw "Mehrere Pipelines heißen exakt '$PipelineName'."
}

if ($matches.Count -eq 1) {
    Write-Host "[EXISTS] Pipeline $PipelineName" -ForegroundColor DarkGray
    Write-Host "         Pipeline ID: $($matches[0].id)" -ForegroundColor DarkGray
    return
}

if (-not $Apply) {
    Write-Host "[PLAN] Register temporary AzureRM-WIF bridge test pipeline $PipelineName" -ForegroundColor Yellow
    Write-Host "       Source: $Project/$Repository/$YamlPath" -ForegroundColor DarkGray
    Write-Host '       First run will NOT be started automatically.' -ForegroundColor DarkGray
    return
}

Write-Host "[CREATE] Pipeline $PipelineName" -ForegroundColor Green
$create = Invoke-BSSEAz -Arguments @(
    'pipelines','create',
    '--org',$OrganizationUrl,
    '--project',$Project,
    '--name',$PipelineName,
    '--repository',$Repository,
    '--repository-type','tfsgit',
    '--branch','main',
    '--yml-path',$YamlPath,
    '--skip-first-run','true',
    '--output','json',
    '--only-show-errors'
)
if ($create.ExitCode -ne 0) {
    throw "Temporäre Bridge-Testpipeline konnte nicht registriert werden.`n$($create.Output)"
}

$created = $create.Output | ConvertFrom-Json
Write-Host "[OK] Temporäre Testpipeline $PipelineName registriert." -ForegroundColor Green
Write-Host "     Pipeline ID: $($created.id)" -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Pipeline-spezifische Autorisierung der Bridge-Service-Connection wird separat im lokalen Bridge-Setup verifiziert.' -ForegroundColor DarkGray
