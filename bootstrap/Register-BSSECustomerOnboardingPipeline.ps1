[CmdletBinding()]
param(
    [string]$OrganizationUrl = 'https://dev.azure.com/BSSE-CloudOps/',
    [string]$Project = '00-Platform',
    [string]$Repository = 'PlatformBootstrap',
    [string]$PipelineName = 'Customer-Onboarding',
    [string]$YamlPath = 'pipelines/customer-onboarding.yml',
    [string]$ServiceConnectionName = 'sc-platform-bootstrap-azdo',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"

$session = Initialize-BSSEAzureDevOpsSession -OrganizationUrl $OrganizationUrl
$OrganizationUrl = $session.OrganizationUrl

Write-Host ''
Write-Host 'BSSE Customer-Onboarding Pipeline Registration' -ForegroundColor Cyan
Write-Host "Organization:       $OrganizationUrl"
Write-Host "Project:            $Project"
Write-Host "Repository:         $Repository"
Write-Host "Pipeline:           $PipelineName"
Write-Host "YAML:               $YamlPath"
Write-Host "Service Connection: $ServiceConnectionName"
Write-Host "Mode:               $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"
Write-Host ''

if (-not (Test-BSSEProjectExists -OrganizationUrl $OrganizationUrl -Project $Project)) {
    throw "Azure-DevOps-Projekt '$Project' existiert nicht. Führe zuerst New-BSSEAzureDevOpsCore.ps1 aus."
}

$repos = @(Get-BSSEProjectRepositories -OrganizationUrl $OrganizationUrl -Project $Project)
$repo = $repos | Where-Object { $_.name -eq $Repository } | Select-Object -First 1
if (-not $repo) {
    throw "Repository '$Project/$Repository' existiert nicht."
}
Write-Host "[OK] Repository $Project/$Repository vorhanden." -ForegroundColor Green

$serviceEndpointsJson = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'devops','service-endpoint','list',
    '--org', $OrganizationUrl,
    '--project', $Project,
    '--output','json',
    '--only-show-errors'
)
$serviceEndpoints = @($serviceEndpointsJson | ConvertFrom-Json)
$serviceConnection = $serviceEndpoints | Where-Object { $_.name -eq $ServiceConnectionName } | Select-Object -First 1

if (-not $serviceConnection) {
    Write-Host "[BLOCKED] Service Connection '$ServiceConnectionName' fehlt." -ForegroundColor Red
    Write-Host '          Diese privilegierte WIF-/Entra-Verbindung wird bewusst nicht automatisch mit erhöhten Rechten erzeugt.' -ForegroundColor DarkGray
    Write-Host '          Erstelle sie einmalig in 00-Platform und starte diesen Bootstrap danach erneut.' -ForegroundColor DarkGray
    if ($Apply) {
        throw "Service Connection '$ServiceConnectionName' fehlt."
    }
    return
}

Write-Host "[OK] Service Connection $ServiceConnectionName vorhanden." -ForegroundColor Green

$pipelinesJson = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'pipelines','list',
    '--org', $OrganizationUrl,
    '--project', $Project,
    '--output','json',
    '--only-show-errors'
)
$pipelines = @($pipelinesJson | ConvertFrom-Json)
$existingPipeline = $pipelines | Where-Object { $_.name -eq $PipelineName } | Select-Object -First 1

if ($existingPipeline) {
    Write-Host "[EXISTS] Pipeline $PipelineName (no change)" -ForegroundColor DarkGray
    return
}

if (-not $Apply) {
    Write-Host "[PLAN] Register pipeline $PipelineName from $Project/$Repository/$YamlPath" -ForegroundColor Yellow
    Write-Host '       First run will be skipped; testing remains an explicit later action.' -ForegroundColor DarkGray
    return
}

Write-Host "[CREATE] Pipeline $PipelineName" -ForegroundColor Green
Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'pipelines','create',
    '--org', $OrganizationUrl,
    '--project', $Project,
    '--name', $PipelineName,
    '--repository', $Repository,
    '--repository-type', 'tfsgit',
    '--branch', 'main',
    '--yml-path', $YamlPath,
    '--skip-first-run', 'true',
    '--only-show-errors'
) | Out-Null

$pipelinesJson = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'pipelines','list',
    '--org', $OrganizationUrl,
    '--project', $Project,
    '--output','json',
    '--only-show-errors'
)
$pipelines = @($pipelinesJson | ConvertFrom-Json)
$created = $pipelines | Where-Object { $_.name -eq $PipelineName } | Select-Object -First 1

if (-not $created) {
    throw "Pipeline '$PipelineName' wurde nach der Erstellung nicht wiedergefunden."
}

Write-Host "[OK] Pipeline $PipelineName registriert; erster Lauf wurde nicht automatisch gestartet." -ForegroundColor Green
