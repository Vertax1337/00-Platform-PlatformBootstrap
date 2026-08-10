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

    # Accept both native PowerShell arrays and comma/semicolon-separated values
    # passed through pwsh.exe -File, e.g.:
    # -Modules AzureDocumentation,OPNsenseDocumentation
    [string[]]$Modules = @(),

    # Same tolerant handling for firewall/site names.
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

function Get-FirewallDefinitions {
    param(
        [string[]]$Names,
        [string]$CustomerProjectSlug
    )

    $definitions = @()
    $repoNames = @{}

    foreach ($name in @($Names)) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Firewall-Bezeichnungen dürfen nicht leer sein."
        }

        $siteSlug = ConvertTo-BSSESlug -Value $name -MaxLength 48
        $repoName = "Firewall-$CustomerProjectSlug-$siteSlug"

        if ($repoName.Length -gt 128) {
            throw "Der erzeugte Repository-Name ist zu lang: $repoName"
        }

        if ($repoNames.ContainsKey($repoName.ToLowerInvariant())) {
            throw "Mehrere Firewall-Bezeichnungen ergeben denselben Repository-Namen: $repoName"
        }

        $repoNames[$repoName.ToLowerInvariant()] = $true

        $definitions += [pscustomobject]@{
            Name       = $name
            SiteSlug   = $siteSlug
            Repository = $repoName
        }
    }

    return @($definitions)
}

function New-CustomerScaffold {
    param(
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Number,
        [Parameter(Mandatory)][string]$Slug,
        [string]$AzureTenantId,
        [string[]]$EnabledModules,
        [object[]]$FirewallDefinitions
    )

    $base = Join-Path (Split-Path $PSScriptRoot -Parent) "generated-customers\$ProjectName"

    if (Test-Path $base) {
        Remove-Item -Recurse -Force $base
    }

    New-Item -ItemType Directory -Path $base -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base 'documentation') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base 'infrastructure') -Force | Out-Null

    $moduleMap = @{
        AzureDocumentation    = $EnabledModules -contains 'AzureDocumentation'
        OPNsenseDocumentation = $EnabledModules -contains 'OPNsenseDocumentation'
        AVD                   = $EnabledModules -contains 'AVD'
        Vaultwarden           = $EnabledModules -contains 'Vaultwarden'
    }

    $tenantValue = if ([string]::IsNullOrWhiteSpace($AzureTenantId)) { 'null' } else { $AzureTenantId }

    $lines = @(
        'customer:',
        "  number: `"$Number`"",
        "  name: `"$DisplayName`"",
        "  slug: `"$Slug`"",
        "  project: `"$ProjectName`"",
        "  tenantId: $tenantValue",
        '',
        'modules:',
        "  azureDocumentation: $($moduleMap.AzureDocumentation.ToString().ToLowerInvariant())",
        "  opnsenseDocumentation: $($moduleMap.OPNsenseDocumentation.ToString().ToLowerInvariant())",
        "  avd: $($moduleMap.AVD.ToString().ToLowerInvariant())",
        "  vaultwarden: $($moduleMap.Vaultwarden.ToString().ToLowerInvariant())",
        '',
        $(if ($FirewallDefinitions.Count) { 'firewalls:' } else { 'firewalls: []' })
    )

    if ($FirewallDefinitions.Count) {
        foreach ($fw in $FirewallDefinitions) {
            $lines += "  - id: `"$($fw.SiteSlug)`""
            $lines += "    name: `"$($fw.Name)`""
            $lines += "    platform: `"OPNsense`""
            $lines += "    repository: `"$($fw.Repository)`""
            $lines += "    classification: `"RAW-CONFIDENTIAL`""
            $lines += "    purpose: `"os-git-backup`""
        }
    }

    Set-Content -Path (Join-Path $base 'customer.yml') -Value ($lines -join [Environment]::NewLine) -Encoding utf8

    if ($moduleMap.AzureDocumentation) {
        @"
azure:
  tenantId: $tenantValue
  serviceConnection: sc-cust$Number-azure-reader

collect:
  resourceGroups: true
  virtualMachines: true
  networking: true
  storage: true
  appServices: true
  backup: true
"@ | Set-Content -Path (Join-Path $base 'documentation\azure.yml') -Encoding utf8
    }

    if ($moduleMap.OPNsenseDocumentation) {
        $rawRepoYaml = if ($FirewallDefinitions.Count) {
            "rawRepositories:`n" + (($FirewallDefinitions | ForEach-Object { "    - `"$($_.Repository)`"" }) -join [Environment]::NewLine)
        }
        else {
            'rawRepositories: []'
        }

        @"
opnsense:
  inputPolicy: sanitized-only
  requireSanitizationReport: true
  rejectRawConfig: true
  $rawRepoYaml
"@ | Set-Content -Path (Join-Path $base 'documentation\opnsense.yml') -Encoding utf8
    }

    if ($moduleMap.AVD) {
        $avdDir = Join-Path $base 'infrastructure\avd'
        New-Item -ItemType Directory -Path $avdDir -Force | Out-Null
        "Kundenspezifische, nicht-geheime Parameter für 20-IaC/AVD-Accelerator." |
            Set-Content -Path (Join-Path $avdDir 'README.md') -Encoding utf8
    }

    if ($moduleMap.Vaultwarden) {
        $vwDir = Join-Path $base 'infrastructure\vaultwarden'
        New-Item -ItemType Directory -Path $vwDir -Force | Out-Null
        "Kundenspezifische, nicht-geheime Parameter für 20-IaC/Vaultwarden." |
            Set-Content -Path (Join-Path $vwDir 'README.md') -Encoding utf8
    }

    return $base
}

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

$Modules = @(Expand-BSSEListArgument -Values $Modules)
$Firewalls = @(Expand-BSSEListArgument -Values $Firewalls)

$allowedModules = @(
    'AzureDocumentation',
    'OPNsenseDocumentation',
    'AVD',
    'Vaultwarden'
)

$invalidModules = @(
    $Modules | Where-Object { $allowedModules -notcontains $_ }
)

if ($invalidModules.Count) {
    throw "Ungültige Module: $($invalidModules -join ', '). Erlaubt sind: $($allowedModules -join ', ')."
}

# Remove duplicate entries while preserving first occurrence order.
$seenModules = @{}
$Modules = @(
    foreach ($module in $Modules) {
        $key = $module.ToLowerInvariant()
        if (-not $seenModules.ContainsKey($key)) {
            $seenModules[$key] = $true
            $module
        }
    }
)

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

if ([string]::IsNullOrWhiteSpace($CustomerSlug)) {
    $CustomerSlug = ConvertTo-BSSESlug -Value $CustomerName
}

$requestedProjectName = "CUST-$CustomerNumber-$CustomerSlug"
$baseRepositories = @('CustomerConfiguration', 'Documentation')

$json = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'devops','project','list',
    '--org', $OrganizationUrl,
    '--output','json',
    '--only-show-errors'
)

$projects = @((($json | ConvertFrom-Json).value) | ForEach-Object { $_.name })

# CustomerNumber is the stable technical identity. If the company was renamed,
# reuse the already existing CUST-<number>-* project instead of creating a duplicate.
$customerPrefix = "CUST-$CustomerNumber-"
$matchingProjects = @(
    $projects | Where-Object {
        $_.StartsWith($customerPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    }
)

if ($matchingProjects.Count -gt 1) {
    throw "Mehrere Azure-DevOps-Projekte verwenden dieselbe CustomerNumber '$CustomerNumber': $($matchingProjects -join ', '). Die Kunden-ID muss eindeutig sein."
}

if ($matchingProjects.Count -eq 1) {
    $projectName = $matchingProjects[0]
    $projectExists = $true
    $effectiveCustomerSlug = $projectName.Substring($customerPrefix.Length)

    if ($projectName -ne $requestedProjectName) {
        Write-Host "[AUTO] Bestehender Kunde über CustomerNumber gefunden: $projectName" -ForegroundColor DarkCyan
        Write-Host "       Angegebener aktueller Name: $CustomerName" -ForegroundColor DarkGray
        Write-Host "       Projektname bleibt stabil; eine Umfirmierung erzeugt kein zweites Kundenprojekt." -ForegroundColor DarkGray
    }
}
else {
    $projectName = $requestedProjectName
    $projectExists = $false
    $effectiveCustomerSlug = $CustomerSlug
}

$firewallDefinitions = @(Get-FirewallDefinitions -Names $Firewalls -CustomerProjectSlug $effectiveCustomerSlug)

Write-Host ""
Write-Host "BSSE Customer Onboarding" -ForegroundColor Cyan
Write-Host "Customer number: $CustomerNumber"
Write-Host "Customer name:   $CustomerName"
Write-Host "Project:         $projectName"
Write-Host "Modules:         $(if ($Modules.Count) { $Modules -join ', ' } else { '<none selected yet>' })"
Write-Host "Tenant ID:       $(if ($TenantId) { $TenantId } else { '<not specified>' })"
Write-Host "Firewalls:       $(if ($firewallDefinitions.Count) { ($firewallDefinitions.Name -join ', ') } else { '<none>' })"
Write-Host "Mode:            $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"
Write-Host ""

if ($projectExists) {
    Write-Host "[EXISTS] Project $projectName" -ForegroundColor DarkGray
    $repos = @(Get-BSSEProjectRepositories -OrganizationUrl $OrganizationUrl -Project $projectName)
    $repoNames = @($repos | ForEach-Object { $_.name })

    foreach ($repo in $baseRepositories) {
        if ($repoNames -contains $repo) {
            Write-Host "  [EXISTS] Repo $repo" -ForegroundColor DarkGray
            continue
        }

        if ($repo -eq 'CustomerConfiguration') {
            $projectNamedRepo = $repos | Where-Object { $_.name -eq $projectName } | Select-Object -First 1

            if ($projectNamedRepo) {
                if (-not $Apply) {
                    Write-Host "  [PLAN] Rename initial repo '$projectName' -> 'CustomerConfiguration'" -ForegroundColor Yellow
                }
                else {
                    Write-Host "  [RENAME] Initial repo '$projectName' -> 'CustomerConfiguration'" -ForegroundColor Green
                    Invoke-BSSEAzDevOpsOrThrow -Arguments @(
                        'repos','update',
                        '--org', $OrganizationUrl,
                        '--project', $projectName,
                        '--repository', $projectNamedRepo.id,
                        '--name', 'CustomerConfiguration',
                        '--only-show-errors'
                    ) | Out-Null

                    $repoNames = @($repoNames | Where-Object { $_ -ne $projectName }) + 'CustomerConfiguration'
                }
                continue
            }
        }

        if (-not $Apply) {
            Write-Host "  [PLAN] Create repo $repo" -ForegroundColor Yellow
        }
        else {
            Write-Host "  [CREATE] Repo $repo" -ForegroundColor Green
            New-BSSEEmptyGitRepository `
                -OrganizationUrl $OrganizationUrl `
                -Project $projectName `
                -RepositoryName $repo

            $repoNames += $repo
        }
    }
}
elseif (-not $Apply) {
    Write-Host "[PLAN] Create private project $projectName" -ForegroundColor Yellow
    Write-Host "  [PLAN] Rename initial Git repo '$projectName' -> 'CustomerConfiguration'" -ForegroundColor Yellow
    Write-Host "  [PLAN] Create repo Documentation" -ForegroundColor Yellow
    $repoNames = @()
}
else {
    Write-Host "[CREATE] Project $projectName" -ForegroundColor Green

    Invoke-BSSEAzDevOpsOrThrow -Arguments @(
        'devops','project','create',
        '--org', $OrganizationUrl,
        '--name', $projectName,
        '--description', "BSSE customer boundary for $CustomerName (Customer/Debtor $CustomerNumber).",
        '--process', 'Basic',
        '--source-control', 'git',
        '--visibility', 'private',
        '--only-show-errors'
    ) | Out-Null

    $repos = @(Get-BSSEProjectRepositories -OrganizationUrl $OrganizationUrl -Project $projectName)
    $initialRepo = $repos | Where-Object { $_.name -eq $projectName } | Select-Object -First 1

    if (-not $initialRepo) {
        throw "Das von Azure DevOps automatisch erzeugte Initial-Repository '$projectName' wurde nicht gefunden."
    }

    Write-Host "  [RENAME] Initial repo '$projectName' -> 'CustomerConfiguration'" -ForegroundColor Green

    Invoke-BSSEAzDevOpsOrThrow -Arguments @(
        'repos','update',
        '--org', $OrganizationUrl,
        '--project', $projectName,
        '--repository', $initialRepo.id,
        '--name', 'CustomerConfiguration',
        '--only-show-errors'
    ) | Out-Null

    Write-Host "  [CREATE] Repo Documentation" -ForegroundColor Green

    New-BSSEEmptyGitRepository `
        -OrganizationUrl $OrganizationUrl `
        -Project $projectName `
        -RepositoryName 'Documentation'

    $repoNames = @('CustomerConfiguration','Documentation')
}

Write-Host ""
Write-Host "Firewall RAW backup repositories:" -ForegroundColor Cyan

if (-not $firewallDefinitions.Count) {
    Write-Host "  <none requested>" -ForegroundColor DarkGray
}
else {
    if ($projectExists -or $Apply) {
        if (-not $repoNames) {
            $repos = @(Get-BSSEProjectRepositories -OrganizationUrl $OrganizationUrl -Project $projectName)
            $repoNames = @($repos | ForEach-Object { $_.name })
        }
    }

    foreach ($fw in $firewallDefinitions) {
        if (($projectExists -or $Apply) -and ($repoNames -contains $fw.Repository)) {
            Write-Host "  [EXISTS] $($fw.Repository)" -ForegroundColor DarkGray
        }
        elseif (-not $Apply) {
            Write-Host "  [PLAN] Create EMPTY RAW repo $($fw.Repository)" -ForegroundColor Yellow
            Write-Host "         OPNsense os-git-backup target; NO README / NO initial commit" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  [CREATE] EMPTY RAW repo $($fw.Repository)" -ForegroundColor Green

            New-BSSEEmptyGitRepository `
                -OrganizationUrl $OrganizationUrl `
                -Project $projectName `
                -RepositoryName $fw.Repository

            Write-Host "           Repository intentionally left completely empty." -ForegroundColor DarkGray
            Write-Host "           Classification: RAW-CONFIDENTIAL / OPNsense config backup" -ForegroundColor DarkGray
            $repoNames += $fw.Repository
        }
    }
}

Write-Host ""
Write-Host "Module plan:" -ForegroundColor Cyan

if ($Modules -contains 'AzureDocumentation') {
    Write-Host "  [MODULE] Azure documentation" -ForegroundColor Green
    Write-Host "           Service Connection target: sc-cust$CustomerNumber-azure-reader"
}

if ($Modules -contains 'OPNsenseDocumentation') {
    Write-Host "  [MODULE] OPNsense documentation" -ForegroundColor Green
    Write-Host "           RAW config is read from dedicated Firewall-* repositories." -ForegroundColor DarkGray
    Write-Host "           Only sanitized/validated data may continue into documentation/AI." -ForegroundColor DarkGray

    if (-not $firewallDefinitions.Count) {
        Write-Warning "OPNsenseDocumentation ist aktiviert, aber es wurde noch keine Firewall über -Firewalls angegeben."
    }
}

if ($Modules -contains 'AVD') {
    Write-Host "  [MODULE] AVD Accelerator IaC" -ForegroundColor Green
    Write-Host "           Service Connection target: sc-cust$CustomerNumber-avd-deploy"
}

if ($Modules -contains 'Vaultwarden') {
    Write-Host "  [MODULE] Vaultwarden IaC" -ForegroundColor Green
    Write-Host "           Service Connection target: sc-cust$CustomerNumber-vaultwarden-deploy"
}

if (-not $Modules.Count) {
    Write-Host "  No modules selected. This is valid; modules can be added later." -ForegroundColor DarkGray
}

if ($firewallDefinitions.Count -and ($Modules -notcontains 'OPNsenseDocumentation')) {
    Write-Host ""
    Write-Host "[INFO] Firewall backup repositories were requested without the OPNsenseDocumentation module." -ForegroundColor DarkCyan
    Write-Host "       This is supported: backup and documentation are intentionally independent capabilities." -ForegroundColor DarkGray
}

if ($Apply) {
    $scaffold = New-CustomerScaffold `
        -ProjectName $projectName `
        -DisplayName $CustomerName `
        -Number $CustomerNumber `
        -Slug $effectiveCustomerSlug `
        -AzureTenantId $TenantId `
        -EnabledModules $Modules `
        -FirewallDefinitions $firewallDefinitions

    Write-Host ""
    Write-Host "[GENERATED] Local CustomerConfiguration scaffold:" -ForegroundColor Green
    Write-Host "            $scaffold"
}

Write-Host ""
if (-not $Apply) {
    Write-Host "Dry Run abgeschlossen. Es wurden keine Azure-DevOps-Objekte verändert." -ForegroundColor Cyan
}
else {
    Write-Host "Customer project base successfully created/verified." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Firewall security boundary:" -ForegroundColor Yellow
Write-Host "- Firewall-* repositories contain RAW confidential configuration."
Write-Host "- Bootstrap writes NO content to these repositories."
Write-Host "- Repository-level permissions should be more restrictive than ordinary customer source repositories."
Write-Host "- Raw configurations must never be copied into Documentation or 10-Automation."
