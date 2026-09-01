[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$coreBootstrapPath = Join-Path $repoRoot 'bootstrap/New-BSSEAzureDevOpsCore.ps1'

if (-not (Test-Path -LiteralPath $coreBootstrapPath -PathType Leaf)) {
    throw "Core bootstrap not found: $coreBootstrapPath"
}

$content = Get-Content -LiteralPath $coreBootstrapPath -Raw

$expectedCoreProjects = @(
    '00-Platform',
    '10-Automation',
    '20-IaC',
    '30-IDD',
    '99-LAB'
)

foreach ($projectName in $expectedCoreProjects) {
    $needle = "Name = '$projectName'"
    if (-not $content.Contains($needle)) {
        throw "Core project contract missing '$projectName'."
    }
}

$iddBlockPattern = "(?s)@\{\s*Name = '30-IDD'\s*Description = '[^']+'\s*Repositories = @\('IntuneDefaultDeployment'\)\s*BrandingPendingReason = '[^']+'\s*\}"
if ($content -notmatch $iddBlockPattern) {
    throw '30-IDD Core contract must contain exactly the initial IntuneDefaultDeployment repository and an explicit pending-branding reason.'
}

$iacIndex = $content.IndexOf("Name = '20-IaC'", [System.StringComparison]::Ordinal)
$iddIndex = $content.IndexOf("Name = '30-IDD'", [System.StringComparison]::Ordinal)
$labIndex = $content.IndexOf("Name = '99-LAB'", [System.StringComparison]::Ordinal)
if ($iacIndex -lt 0 -or $iddIndex -lt 0 -or $labIndex -lt 0 -or -not ($iacIndex -lt $iddIndex -and $iddIndex -lt $labIndex)) {
    throw '30-IDD must remain a Core project between 20-IaC and 99-LAB in the declared platform order.'
}

Write-Host '[OK] Core project contract includes 30-IDD with the minimal IntuneDefaultDeployment repository contract.' -ForegroundColor Green
