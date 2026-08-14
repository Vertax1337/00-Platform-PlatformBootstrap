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

    # Documentation capabilities only. IaC products such as AVD/Vaultwarden
    # are intentionally not accepted by this customer-documentation onboarding.
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
. "$PSScriptRoot\BSSE.AzureDevOps.CustomerProject.ps1"
. "$PSScriptRoot\BSSE.AzureDevOps.Branding.ps1"

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
        [string[]]$EnabledDocumentationModules,
        [object[]]$FirewallDefinitions
    )

    $base = Join-Path (Split-Path $PSScriptRoot -Parent) "generated-customers\$ProjectName"

    if (Test-Path $base) {
        Remove-Item -Recurse -Force $base
    }

    New-Item -ItemType Directory -Path $base -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base 'documentation') -Force | Out-Null

    $moduleMap = @{
        AzureDocumentation    = $EnabledDocumentationModules -contains 'AzureDocumentation'
        OPNsenseDocumentation = $EnabledDocumentationModules -contains 'OPNsenseDocumentation'
    }

    $tenantValue = if ([string]::IsNullOrWhiteSpace($AzureTenantId)) { 'null' } else { $AzureTenantId }

    # Keep the established customer.yml key 'modules:' for compatibility.
    # Its values now represent documentation modules only.
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

$iacProducts = @(
    $Modules | Where-Object { $_ -in @('AVD','Vaultwarden','AVD-Accelerator') }
)

if ($iacProducts.Count) {
    throw @"
AVD/Vaultwarden sind IaC-Produkte und keine Dokumentationsmodule.
Sie dürfen nicht über New-BSSECustomerProject.ps1 bzw. die Customer-Onboarding-Dokumentationspipeline aktiviert werden.

Angefordert: $($iacProducts -join ', ')

IaC-Deployments werden getrennt unter 20-IaC mit eigenen Deployment-Pipelines,
Service Connections, Plan/What-If, Approval und Deploy/Verify behandelt.
"@
}

$allowedModules = @(
    'AzureDocumentation',
    'OPNsenseDocumentation'
)

$invalidModules = @(
    $Modules | Where-Object { $allowedModules -notcontains $_ }
)

if ($invalidModules.Count) {
    throw "Ungültige Dokumentationsmodule: $($invalidModules -join ', '). Erlaubt sind: $($allowedModules -join ', ')."
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

$resolution = Resolve-BSSECustomerProject `
    -OrganizationUrl $OrganizationUrl `
    -CustomerNumber $CustomerNumber `
    -RequestedProjectName $requestedProjectName `
    -DirectLookupAttempts 3

$projectName = $resolution.ProjectName
$projectExists = $resolution.Exists
$effectiveCustomerSlug = $resolution.EffectiveSlug

if ($projectExists) {
    Assert-BSSECustomerProjectReadable `
        -OrganizationUrl $OrganizationUrl `
        -ProjectName $projectName | Out-Null

    if (-not $projectName.Equals($requestedProjectName, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "[AUTO] Bestehender Kunde über CustomerNumber gefunden: $projectName" -ForegroundColor DarkCyan
        Write-Host "       Angegebener aktueller Name: $CustomerName" -ForegroundColor DarkGray
        Write-Host "       Projektname bleibt stabil; eine Umfirmierung erzeugt kein zweites Kundenprojekt." -ForegroundColor DarkGray
    }
}

$firewallDefinitions = @(Get-FirewallDefinitions -Names $Firewalls -CustomerProjectSlug $effectiveCustomerSlug)

Write-Host ""
Write-Host "BSSE Customer Onboarding - Documentation" -ForegroundColor Cyan
Write-Host "Customer number:       $CustomerNumber"
Write-Host "Customer name:         $CustomerName"
Write-Host "Project:               $projectName"
Write-Host "Documentation modules: $(if ($Modules.Count) { $Modules -join ', ' } else { '<none selected>' })"
Write-Host "Tenant ID:             $(if ($TenantId) { $TenantId } else { '<not specified>' })"
Write-Host "Firewalls:             $(if ($firewallDefinitions.Count) { ($firewallDefinitions.Name -join ', ') } else { '<none>' })"
Write-Host "Mode:                  $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"
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

    $createResult = Invoke-BSSEAz -Arguments @(
        'devops','project','create',
        '--org', $OrganizationUrl,
        '--name', $projectName,
        '--description', "BSSE customer boundary for $CustomerName (Customer/Debtor $CustomerNumber).",
        '--process', 'Basic',
        '--source-control', 'git',
        '--visibility', 'private',
        '--output','json',
        '--only-show-errors'
    )

    if ($createResult.ExitCode -ne 0) {
        if ($createResult.Output -match 'TF200019|already exists') {
            Write-Host "[RECOVER] Azure DevOps reports that '$projectName' already exists. Resolving existing state instead of creating a duplicate." -ForegroundColor DarkCyan

            $recovery = Resolve-BSSECustomerProject `
                -OrganizationUrl $OrganizationUrl `
                -CustomerNumber $CustomerNumber `
                -RequestedProjectName $projectName `
                -DirectLookupAttempts 5

            if ($recovery.Exists) {
                Assert-BSSECustomerProjectReadable `
                    -OrganizationUrl $OrganizationUrl `
                    -ProjectName $recovery.ProjectName | Out-Null

                $retryParameters = @{
                    OrganizationUrl = $OrganizationUrl
                    CustomerNumber  = $CustomerNumber
                    CustomerName    = $CustomerName
                    CustomerSlug    = $CustomerSlug
                    Modules         = @($Modules)
                    Firewalls       = @($Firewalls)
                    TenantId        = $TenantId
                    Apply           = $true
                }

                Write-Host "[RECOVER] Existing project resolved as '$($recovery.ProjectName)'. Re-entering reconciliation path." -ForegroundColor DarkCyan
                & $PSCommandPath @retryParameters
                return
            }

            Write-Host "[BLOCKED] Azure DevOps says project '$projectName' exists, but the bootstrap identity cannot resolve it." -ForegroundColor Red
            throw @"
Azure DevOps meldet TF200019 / already exists für '$projectName',
der vorhandene Projektzustand ist für die Bootstrap-Identität aber nicht belastbar auflösbar.

Es wird absichtlich KEIN weiterer Create-Versuch durchgeführt.
Prüfe projektbezogenen Zugriff bzw. den Zustand des bereits angelegten Projekts.

Originalfehler:
$($createResult.Output)
"@
        }

        throw "Azure DevOps CLI command failed:`naz devops project create --org $OrganizationUrl --name $projectName`n$($createResult.Output)"
    }

    Assert-BSSECustomerProjectReadable `
        -OrganizationUrl $OrganizationUrl `
        -ProjectName $projectName | Out-Null

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
Write-Host "Project branding:" -ForegroundColor Cyan
Ensure-BSSEProjectAvatar `
    -OrganizationUrl $OrganizationUrl `
    -ProjectName $projectName `
    -Apply:$Apply | Out-Null

Write-Host ""
Write-Host "Documentation plan:" -ForegroundColor Cyan

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

if (-not $Modules.Count) {
    Write-Host "  No documentation module selected. Customer base provisioning / firewall backup can still be valid." -ForegroundColor DarkGray
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
        -EnabledDocumentationModules $Modules `
        -FirewallDefinitions $firewallDefinitions

    Write-Host ""
    Write-Host "[GENERATED] Local CustomerConfiguration documentation scaffold:" -ForegroundColor Green
    Write-Host "            $scaffold"
}

Write-Host ""
if (-not $Apply) {
    Write-Host "Dry Run abgeschlossen. Es wurden keine Azure-DevOps-Objekte verändert." -ForegroundColor Cyan
}
else {
    Write-Host "Customer project/documentation base and managed project branding successfully created/verified." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Architecture boundary:" -ForegroundColor Yellow
Write-Host "- AzureDocumentation and OPNsenseDocumentation belong to the documentation platform."
Write-Host "- AVD and Vaultwarden are IaC products under 20-IaC and are NOT deployed by this workflow."
Write-Host "- Firewall-* repositories contain RAW confidential configuration."
Write-Host "- Bootstrap writes NO content to Firewall-* repositories."
Write-Host "- Repository-level permissions should be more restrictive than ordinary customer source repositories."
Write-Host "- Raw configurations must never be copied into Documentation or 10-Automation."