[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OrganizationUrl,

    [Parameter(Mandatory)]
    [Alias('DebitorNumber','Debitorennummer','CustomerId')]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$')]
    [string]$CustomerNumber,

    [Parameter(Mandatory)]
    [string[]]$Firewalls,

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"

function Expand-BSSEListArgument {
    param(
        [string[]]$Values
    )

    $result = @()

    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        foreach ($item in ($value -split '[,;]')) {
            $trimmed = $item.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $result += $trimmed
            }
        }
    }

    return @($result)
}

$Firewalls = @(Expand-BSSEListArgument -Values $Firewalls)

$seenFirewalls = @{}
$Firewalls = @(
    foreach ($firewall in $Firewalls) {
        $key = $firewall.ToLowerInvariant()
        if (-not $seenFirewalls.ContainsKey($key)) {
            $seenFirewalls[$key] = $true
            $firewall
        }
    }
)

$session = Initialize-BSSEAzureDevOpsSession -OrganizationUrl $OrganizationUrl
$OrganizationUrl = $session.OrganizationUrl

$json = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'devops','project','list',
    '--org', $OrganizationUrl,
    '--output','json',
    '--only-show-errors'
)

$projects = @((($json | ConvertFrom-Json).value) | ForEach-Object { $_.name })
$customerPrefix = "CUST-$CustomerNumber-"

$matchingProjects = @(
    $projects | Where-Object {
        $_.StartsWith($customerPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    }
)

if ($matchingProjects.Count -eq 0) {
    throw "Kein Kundenprojekt mit CustomerNumber '$CustomerNumber' gefunden. Zuerst New-BSSECustomerProject.ps1 verwenden."
}

if ($matchingProjects.Count -gt 1) {
    throw "Mehrere Kundenprojekte verwenden CustomerNumber '$CustomerNumber': $($matchingProjects -join ', '). Die Kunden-ID muss eindeutig sein."
}

$projectName = $matchingProjects[0]
$customerSlug = $projectName.Substring($customerPrefix.Length)

$repos = @(Get-BSSEProjectRepositories -OrganizationUrl $OrganizationUrl -Project $projectName)
$repoNames = @($repos | ForEach-Object { $_.name })
$planned = @{}

Write-Host ""
Write-Host "BSSE Firewall Repository Onboarding" -ForegroundColor Cyan
Write-Host "Customer number: $CustomerNumber"
Write-Host "Project:         $projectName"
Write-Host "Mode:            $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"
Write-Host ""

foreach ($firewall in $Firewalls) {
    if ([string]::IsNullOrWhiteSpace($firewall)) {
        throw "Firewall-Bezeichnungen dürfen nicht leer sein."
    }

    $siteSlug = ConvertTo-BSSESlug -Value $firewall -MaxLength 48
    $repoName = "Firewall-$customerSlug-$siteSlug"
    $key = $repoName.ToLowerInvariant()

    if ($planned.ContainsKey($key)) {
        throw "Mehrere Firewall-Bezeichnungen ergeben denselben Repository-Namen: $repoName"
    }

    $planned[$key] = $true

    if ($repoNames -contains $repoName) {
        Write-Host "[EXISTS] $repoName" -ForegroundColor DarkGray
        continue
    }

    if (-not $Apply) {
        Write-Host "[PLAN] Create EMPTY RAW repo $repoName" -ForegroundColor Yellow
        Write-Host "       OPNsense os-git-backup target; NO README / NO initial commit" -ForegroundColor DarkGray
        continue
    }

    Write-Host "[CREATE] EMPTY RAW repo $repoName" -ForegroundColor Green

    New-BSSEEmptyGitRepository `
        -OrganizationUrl $OrganizationUrl `
        -Project $projectName `
        -RepositoryName $repoName

    Write-Host "         Repository intentionally left completely empty." -ForegroundColor DarkGray
    $repoNames += $repoName
}

Write-Host ""
if (-not $Apply) {
    Write-Host "Dry Run abgeschlossen. Es wurden keine Azure-DevOps-Objekte verändert." -ForegroundColor Cyan
}
else {
    Write-Host "Firewall-Repositories wurden idempotent geprüft/ergänzt." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "WICHTIG:" -ForegroundColor Yellow
Write-Host "Diese Repositories sind RAW-CONFIDENTIAL und ausschließlich als OPNsense os-git-backup Upstream vorgesehen."
Write-Host "Keine README, keine Pipeline-Datei, kein Initial-Commit und keine Sanitized-Daten hineinlegen."
