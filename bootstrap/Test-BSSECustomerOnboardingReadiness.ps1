[CmdletBinding()]
param(
    [string]$OrganizationUrl = 'https://dev.azure.com/BSSE-CloudOps/'
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
Write-Host 'Dieser Check verändert keine Plattform- oder Kundenobjekte.' -ForegroundColor DarkGray
Write-Host ''

$repoRoot = Split-Path $PSScriptRoot -Parent

$requiredLocalFiles = @(
    'BSSE.AzureDevOps.Common.ps1',
    'BSSE.AzureDevOps.Branding.ps1',
    'New-BSSEAzureDevOpsCore.ps1',
    'Initialize-BSSEPlatformDependencies.ps1',
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

$pipelineYaml = Join-Path $repoRoot 'pipelines\customer-onboarding.yml'
if (Test-Path $pipelineYaml) {
    Write-Ready 'Lokale Pipeline-YAML pipelines/customer-onboarding.yml vorhanden.'
}
else {
    Write-NotReady 'Lokale Pipeline-YAML pipelines/customer-onboarding.yml fehlt.'
}

$brandingTest = Join-Path $repoRoot 'tests\Test-BSSEProjectBranding.ps1'
if (Test-Path $brandingTest) {
    Write-Ready 'Branding-Regressionstest tests/Test-BSSEProjectBranding.ps1 vorhanden.'
}
else {
    Write-NotReady 'Branding-Regressionstest tests/Test-BSSEProjectBranding.ps1 fehlt.'
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Ready 'Git verfügbar.'
}
else {
    Write-NotReady 'Git fehlt.'
}

if ($failures.Count -eq 0) {
    Write-Host ''
    Write-Host 'Project branding asset verification:' -ForegroundColor Cyan

    try {
        $brandingOutput = @(& $brandingTest *>&1)
        $brandingOutput | ForEach-Object { Write-Host $_ }
        Write-Ready 'Project-Branding-Mapping und freigegebene Asset-Hashes sind verifiziert.'
    }
    catch {
        Write-NotReady "Project-Branding-Assetprüfung fehlgeschlagen: $($_.Exception.Message)"
    }
}

if ($failures.Count -eq 0) {
    Write-Host ''
    Write-Host 'Platform dependency verification:' -ForegroundColor Cyan

    try {
        $dependencyOutput = @(& "$PSScriptRoot\Initialize-BSSEPlatformDependencies.ps1" `
            -OrganizationUrl $OrganizationUrl *>&1)

        $dependencyOutput | ForEach-Object { Write-Host $_ }
        $dependencyText = ($dependencyOutput | Out-String)

        if ($dependencyText -match '\[BLOCKED\]') {
            Write-NotReady 'Platform dependency verification enthält einen BLOCKED-Zustand.'
        }
        elseif ($dependencyText -match '\[PLAN\]') {
            Write-NotReady 'Platform dependencies sind noch nicht vollständig eingerichtet; Dry Run enthält PLAN-Zustände.'
        }
        else {
            Write-Ready 'Self-hosting Platform-Dependencies einschließlich verwaltetem Core-Project-Branding sind vollständig vorhanden.'
        }
    }
    catch {
        Write-NotReady "Platform dependency verification fehlgeschlagen: $($_.Exception.Message)"
    }
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
Write-Host 'Hinweis: Dies ist ein Readiness-Check, keine Runtime-Verifikation eines Kunden-Onboarding-Laufs.' -ForegroundColor DarkGray
