[CmdletBinding()]
param(
    [string]$OrganizationUrl = 'https://dev.azure.com/BSSE-CloudOps/',
    [string]$Project = '00-Platform',
    [string]$Repository = 'PlatformBootstrap',
    [string]$PipelineName = 'Customer-Onboarding',
    [string]$ServiceConnectionName = 'sc-platform-bootstrap-azdo'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"

$failures = @()

function Write-Ready {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-NotReady {
    param([string]$Message)
    $script:failures += $Message
    Write-Host "[NOT READY] $Message" -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'BSSE Customer-Onboarding Readiness Check' -ForegroundColor Cyan
Write-Host 'Dieser Check verändert keine Azure-DevOps-Objekte.' -ForegroundColor DarkGray
Write-Host ''

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Ready 'Git verfügbar (lokale und Pipeline-CustomerConfiguration-Persistenz).'
}
else {
    Write-NotReady 'Git fehlt.'
}

try {
    $session = Initialize-BSSEAzureDevOpsSession -OrganizationUrl $OrganizationUrl
    $OrganizationUrl = $session.OrganizationUrl
    Write-Ready "Azure-DevOps-Zugriff auf $OrganizationUrl verifiziert."
}
catch {
    Write-NotReady "Azure-DevOps-Session nicht bereit: $($_.Exception.Message)"
}

if ($failures.Count -eq 0) {
    if (Test-BSSEProjectExists -OrganizationUrl $OrganizationUrl -Project $Project) {
        Write-Ready "Projekt $Project vorhanden."

        $repos = @(Get-BSSEProjectRepositories -OrganizationUrl $OrganizationUrl -Project $Project)
        if ($repos.name -contains $Repository) {
            Write-Ready "Repository $Project/$Repository vorhanden."
        }
        else {
            Write-NotReady "Repository $Project/$Repository fehlt."
        }

        try {
            $endpointsJson = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
                'devops','service-endpoint','list',
                '--org', $OrganizationUrl,
                '--project', $Project,
                '--output','json',
                '--only-show-errors'
            )
            $endpoints = @($endpointsJson | ConvertFrom-Json)
            if ($endpoints.name -contains $ServiceConnectionName) {
                Write-Ready "Service Connection $ServiceConnectionName vorhanden."
            }
            else {
                Write-NotReady "Service Connection $ServiceConnectionName fehlt."
            }
        }
        catch {
            Write-NotReady "Service Connections konnten nicht geprüft werden: $($_.Exception.Message)"
        }

        try {
            $pipelinesJson = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
                'pipelines','list',
                '--org', $OrganizationUrl,
                '--project', $Project,
                '--output','json',
                '--only-show-errors'
            )
            $pipelines = @($pipelinesJson | ConvertFrom-Json)
            if ($pipelines.name -contains $PipelineName) {
                Write-Ready "Pipeline $PipelineName registriert."
            }
            else {
                Write-NotReady "Pipeline $PipelineName noch nicht registriert."
            }
        }
        catch {
            Write-NotReady "Pipelines konnten nicht geprüft werden: $($_.Exception.Message)"
        }
    }
    else {
        Write-NotReady "Projekt $Project fehlt."
    }
}

$requiredLocalFiles = @(
    'New-BSSECustomerProject.ps1',
    'Sync-BSSECustomerConfiguration.ps1',
    'Start-BSSECustomerOnboarding.ps1',
    'Register-BSSECustomerOnboardingPipeline.ps1'
)

foreach ($file in $requiredLocalFiles) {
    if (Test-Path (Join-Path $PSScriptRoot $file)) {
        Write-Ready "Lokale Komponente bootstrap/$file vorhanden."
    }
    else {
        Write-NotReady "Lokale Komponente bootstrap/$file fehlt."
    }
}

$pipelineYaml = Join-Path (Split-Path $PSScriptRoot -Parent) 'pipelines\customer-onboarding.yml'
if (Test-Path $pipelineYaml) {
    Write-Ready 'Lokale Pipeline-YAML pipelines/customer-onboarding.yml vorhanden.'
}
else {
    Write-NotReady 'Lokale Pipeline-YAML pipelines/customer-onboarding.yml fehlt.'
}

Write-Host ''
if ($failures.Count) {
    Write-Host 'Customer-Onboarding ist noch nicht vollständig testbereit:' -ForegroundColor Yellow
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Yellow
    }
    exit 2
}

Write-Host '[READY] Lokaler und zentraler Customer-Onboarding-Weg sind von den prüfbaren Voraussetzungen her testbereit.' -ForegroundColor Green
Write-Host 'Hinweis: Dies ist ein Readiness-Check, keine Runtime-Verifikation eines Onboarding-Laufs.' -ForegroundColor DarkGray
