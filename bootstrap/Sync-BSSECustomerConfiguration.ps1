[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OrganizationUrl,

    [Parameter(Mandatory)]
    [Alias('DebitorNumber','Debitorennummer','CustomerId')]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$')]
    [string]$CustomerNumber,

    [Parameter(Mandatory)]
    [string]$CustomerName,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]{0,63}$')]
    [string]$CustomerSlug,

    [string[]]$Modules = @(),
    [string[]]$Firewalls = @(),

    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) { return $true }
        $parsed = [guid]::Empty
        return [guid]::TryParse($_, [ref]$parsed)
    })]
    [string]$TenantId,

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"

function Expand-BSSEListArgument {
    param([string[]]$Values)

    $result = @()
    foreach ($value in @($Values)) {
        if ($null -eq $value) { continue }
        foreach ($item in ($value -split '[,;]')) {
            $trimmed = $item.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $result += $trimmed
            }
        }
    }
    return @($result)
}

function Get-BSSEGitAccessToken {
    if (-not [string]::IsNullOrWhiteSpace($env:SYSTEM_ACCESSTOKEN)) {
        return $env:SYSTEM_ACCESSTOKEN
    }

    $token = Invoke-BSSEAz -Arguments @(
        'account','get-access-token',
        '--resource','499b84ac-1321-427f-aa17-267ca6975798',
        '--query','accessToken',
        '--output','tsv',
        '--only-show-errors'
    )

    if ($token.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($token.Output)) {
        throw @"
Für den sicheren Git-Zugriff auf CustomerConfiguration konnte kein Azure-DevOps-OAuth-Token bezogen werden.

Lokal: prüfe den durch Initialize-BSSEAzureDevOpsSession hergestellten Azure-CLI-Kontext.
Pipeline: verwende die vorgesehene WIF-/AzureCLI@3-Session oder mappe System.AccessToken als SYSTEM_ACCESSTOKEN.
"@
    }

    return $token.Output.Trim()
}

function Invoke-BSSEGit {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$WorkingDirectory
    )

    $previousLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            Set-Location $WorkingDirectory
        }

        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $text = ($output | Out-String).Trim()

        if ($exitCode -ne 0) {
            throw "Git command failed: git $($Arguments -join ' ')`n$text"
        }

        return $text
    }
    finally {
        Set-Location $previousLocation
    }
}

function Get-NormalizedText {
    param([Parameter(Mandatory)][string]$Path)
    $text = Get-Content -Raw -Path $Path
    return (($text -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd("`n")
}

function New-BSSEExpectedCustomerConfiguration {
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$EffectiveSlug,
        [Parameter(Mandatory)][string[]]$EnabledModules,
        [Parameter(Mandatory)][string[]]$FirewallNames
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Destination 'documentation') -Force | Out-Null

    $tenantValue = if ([string]::IsNullOrWhiteSpace($TenantId)) { 'null' } else { $TenantId }
    $azureEnabled = $EnabledModules -contains 'AzureDocumentation'
    $opnsenseEnabled = $EnabledModules -contains 'OPNsenseDocumentation'

    $firewallDefinitions = @()
    $seenFirewallRepos = @{}
    foreach ($firewall in $FirewallNames) {
        $siteSlug = ConvertTo-BSSESlug -Value $firewall -MaxLength 48
        $repoName = "Firewall-$EffectiveSlug-$siteSlug"
        if ($repoName.Length -gt 128) {
            throw "Der erzeugte Repository-Name ist zu lang: $repoName"
        }
        if ($seenFirewallRepos.ContainsKey($repoName.ToLowerInvariant())) {
            throw "Mehrere Firewall-Bezeichnungen ergeben denselben Repository-Namen: $repoName"
        }
        $seenFirewallRepos[$repoName.ToLowerInvariant()] = $true
        $firewallDefinitions += [pscustomobject]@{
            Name = $firewall
            SiteSlug = $siteSlug
            Repository = $repoName
        }
    }

    $customerLines = @(
        'customer:',
        "  number: `"$CustomerNumber`"",
        "  name: `"$CustomerName`"",
        "  slug: `"$EffectiveSlug`"",
        "  project: `"$ProjectName`"",
        "  tenantId: $tenantValue",
        '',
        'modules:',
        "  azureDocumentation: $($azureEnabled.ToString().ToLowerInvariant())",
        "  opnsenseDocumentation: $($opnsenseEnabled.ToString().ToLowerInvariant())",
        '',
        $(if ($firewallDefinitions.Count) { 'firewalls:' } else { 'firewalls: []' })
    )

    foreach ($fw in $firewallDefinitions) {
        $customerLines += "  - id: `"$($fw.SiteSlug)`""
        $customerLines += "    name: `"$($fw.Name)`""
        $customerLines += '    platform: "OPNsense"'
        $customerLines += "    repository: `"$($fw.Repository)`""
        $customerLines += '    classification: "RAW-CONFIDENTIAL"'
        $customerLines += '    purpose: "os-git-backup"'
    }

    Set-Content -Path (Join-Path $Destination 'customer.yml') -Value ($customerLines -join [Environment]::NewLine) -Encoding utf8

    if ($azureEnabled) {
        @"
azure:
  tenantId: $tenantValue
  serviceConnection: sc-cust$CustomerNumber-azure-reader

collect:
  resourceGroups: true
  virtualMachines: true
  networking: true
  storage: true
  appServices: true
  backup: true
"@ | Set-Content -Path (Join-Path $Destination 'documentation\azure.yml') -Encoding utf8
    }

    if ($opnsenseEnabled) {
        $rawRepositories = if ($firewallDefinitions.Count) {
            "rawRepositories:`n" + (($firewallDefinitions | ForEach-Object { "    - `"$($_.Repository)`"" }) -join [Environment]::NewLine)
        }
        else {
            'rawRepositories: []'
        }

        @"
opnsense:
  inputPolicy: sanitized-only
  requireSanitizationReport: true
  rejectRawConfig: true
  $rawRepositories
"@ | Set-Content -Path (Join-Path $Destination 'documentation\opnsense.yml') -Encoding utf8
    }
}

$Modules = @(Expand-BSSEListArgument -Values $Modules)
$Firewalls = @(Expand-BSSEListArgument -Values $Firewalls)

$iacProducts = @($Modules | Where-Object { $_ -in @('AVD','AVD-Accelerator','Vaultwarden') })
if ($iacProducts.Count) {
    throw "IaC-Produkte dürfen nicht über CustomerConfiguration-Dokumentationssync verarbeitet werden: $($iacProducts -join ', ')."
}

$allowedModules = @('AzureDocumentation','OPNsenseDocumentation')
$invalidModules = @($Modules | Where-Object { $allowedModules -notcontains $_ })
if ($invalidModules.Count) {
    throw "Ungültige Dokumentationsmodule: $($invalidModules -join ', ')."
}

$Modules = @($Modules | Select-Object -Unique)
$Firewalls = @($Firewalls | Select-Object -Unique)

$session = Initialize-BSSEAzureDevOpsSession -OrganizationUrl $OrganizationUrl
$OrganizationUrl = $session.OrganizationUrl

if ([string]::IsNullOrWhiteSpace($CustomerSlug)) {
    $CustomerSlug = ConvertTo-BSSESlug -Value $CustomerName
}

$projectList = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'devops','project','list',
    '--org', $OrganizationUrl,
    '--output','json',
    '--only-show-errors'
) | ConvertFrom-Json

$customerPrefix = "CUST-$CustomerNumber-"
$matchingProjects = @(
    $projectList.value |
        ForEach-Object { $_.name } |
        Where-Object { $_.StartsWith($customerPrefix, [System.StringComparison]::OrdinalIgnoreCase) }
)

if ($matchingProjects.Count -gt 1) {
    throw "Mehrere Projekte verwenden CustomerNumber '$CustomerNumber': $($matchingProjects -join ', ')."
}

if ($matchingProjects.Count -eq 0) {
    if ($Apply) {
        throw "Customer project CUST-$CustomerNumber-* existiert noch nicht. Führe zuerst New-BSSECustomerProject.ps1 -Apply aus."
    }

    Write-Host "  [PLAN] Initialize CustomerConfiguration after project provisioning" -ForegroundColor Yellow
    return
}

$projectName = $matchingProjects[0]
$effectiveSlug = $projectName.Substring($customerPrefix.Length)

$repoJson = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'repos','show',
    '--org', $OrganizationUrl,
    '--project', $projectName,
    '--repository', 'CustomerConfiguration',
    '--output','json',
    '--only-show-errors'
)
$repo = $repoJson | ConvertFrom-Json

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    throw "Git wurde nicht gefunden. Für die sichere Persistierung von CustomerConfiguration ist Git erforderlich."
}

$token = Get-BSSEGitAccessToken
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bsse-customerconfig-" + [guid]::NewGuid().ToString('N'))
$expectedDir = Join-Path $tempRoot 'expected'
$cloneDir = Join-Path $tempRoot 'repo'

$oldGitConfigCount = $env:GIT_CONFIG_COUNT
$oldGitConfigKey0 = $env:GIT_CONFIG_KEY_0
$oldGitConfigValue0 = $env:GIT_CONFIG_VALUE_0

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-BSSEExpectedCustomerConfiguration `
        -Destination $expectedDir `
        -ProjectName $projectName `
        -EffectiveSlug $effectiveSlug `
        -EnabledModules $Modules `
        -FirewallNames $Firewalls

    # Pass the OAuth token only through the child-process environment. It is never written to the remote URL or console.
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = 'http.extraHeader'
    $env:GIT_CONFIG_VALUE_0 = "Authorization: Bearer $token"

    Invoke-BSSEGit -Arguments @('clone','--quiet','--no-tags',$repo.remoteUrl,$cloneDir) | Out-Null

    $expectedFiles = @(Get-ChildItem -Path $expectedDir -Recurse -File)
    $missingFiles = @()
    $conflicts = @()

    foreach ($sourceFile in $expectedFiles) {
        $relative = $sourceFile.FullName.Substring($expectedDir.Length).TrimStart('\','/')
        $destination = Join-Path $cloneDir $relative

        if (Test-Path $destination) {
            if ((Get-NormalizedText -Path $sourceFile.FullName) -ne (Get-NormalizedText -Path $destination)) {
                $conflicts += $relative.Replace('\','/')
            }
        }
        else {
            $missingFiles += $relative.Replace('\','/')
        }
    }

    if ($conflicts.Count) {
        $message = "CustomerConfiguration enthält bereits abweichende Bootstrap-Zieldateien: $($conflicts -join ', '). Automatisches Überschreiben ist gesperrt."
        Write-Host "  [BLOCKED] $message" -ForegroundColor Red
        throw $message
    }

    if (-not $missingFiles.Count) {
        Write-Host "  [EXISTS] CustomerConfiguration scaffold (no change)" -ForegroundColor DarkGray
        return
    }

    if (-not $Apply) {
        foreach ($relative in $missingFiles) {
            Write-Host "  [PLAN] Add CustomerConfiguration/$relative" -ForegroundColor Yellow
        }
        return
    }

    foreach ($relative in $missingFiles) {
        $source = Join-Path $expectedDir $relative
        $destination = Join-Path $cloneDir $relative
        $parent = Split-Path $destination -Parent
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -Path $source -Destination $destination -Force
    }

    Invoke-BSSEGit -WorkingDirectory $cloneDir -Arguments @('config','user.name','BSSE PlatformBootstrap') | Out-Null
    Invoke-BSSEGit -WorkingDirectory $cloneDir -Arguments @('config','user.email','platformbootstrap@bsse.local') | Out-Null
    Invoke-BSSEGit -WorkingDirectory $cloneDir -Arguments @('add','--all') | Out-Null

    $status = Invoke-BSSEGit -WorkingDirectory $cloneDir -Arguments @('status','--porcelain')
    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host "  [EXISTS] CustomerConfiguration scaffold (no change)" -ForegroundColor DarkGray
        return
    }

    Invoke-BSSEGit -WorkingDirectory $cloneDir -Arguments @('commit','-m',"Initialize CustomerConfiguration for $projectName") | Out-Null

    $targetBranch = if ($repo.defaultBranch) {
        ([string]$repo.defaultBranch) -replace '^refs/heads/',''
    }
    else {
        'main'
    }

    Invoke-BSSEGit -WorkingDirectory $cloneDir -Arguments @('push','origin',"HEAD:refs/heads/$targetBranch") | Out-Null

    foreach ($relative in $missingFiles) {
        Write-Host "  [PUBLISH] CustomerConfiguration/$relative" -ForegroundColor Green
    }
    Write-Host "  [OK] CustomerConfiguration wurde kontrolliert persistiert." -ForegroundColor Green
}
finally {
    $env:GIT_CONFIG_COUNT = $oldGitConfigCount
    $env:GIT_CONFIG_KEY_0 = $oldGitConfigKey0
    $env:GIT_CONFIG_VALUE_0 = $oldGitConfigValue0

    if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
    }
}
