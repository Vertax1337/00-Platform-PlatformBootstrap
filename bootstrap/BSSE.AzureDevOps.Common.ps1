Set-StrictMode -Version Latest

function ConvertTo-BSSEOrganizationUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl
    )

    $value = $OrganizationUrl.Trim()

    $matches = [regex]::Matches(
        $value,
        'https://dev\.azure\.com/[A-Za-z0-9._-]+/?',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($matches.Count -lt 1) {
        throw "Ungültige Azure-DevOps-URL: '$OrganizationUrl'. Erwartet wird z. B. https://dev.azure.com/BSSE-CloudOps/"
    }

    $normalized = $matches[0].Value.TrimEnd('/') + '/'

    if ($normalized -ne $value) {
        Write-Host "[AUTO] OrganizationUrl normalisiert: $normalized" -ForegroundColor DarkCyan
    }

    return $normalized
}

function ConvertTo-BSSESlug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [int]$MaxLength = 64
    )

    $slug = $Value.Trim()
    $slug = $slug.Replace('Ä','Ae').Replace('Ö','Oe').Replace('Ü','Ue')
    $slug = $slug.Replace('ä','ae').Replace('ö','oe').Replace('ü','ue').Replace('ß','ss')
    $slug = $slug -replace '[^A-Za-z0-9]+','-'
    $slug = $slug.Trim('-')

    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Aus '$Value' konnte kein gültiger Slug erzeugt werden."
    }

    if ($slug.Length -gt $MaxLength) {
        $slug = $slug.Substring(0,$MaxLength).TrimEnd('-')
    }

    return $slug
}

function Invoke-BSSEAz {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$PassThruOutput
    )

    $output = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()

    if ($PassThruOutput -and $text) {
        Write-Host $text
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $text
    }
}

function Invoke-BSSEAzDevOpsOrThrow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $result = Invoke-BSSEAz -Arguments $Arguments

    if ($result.ExitCode -ne 0) {
        throw "Azure DevOps CLI command failed:`naz $($Arguments -join ' ')`n$($result.Output)"
    }

    return $result.Output
}

function Assert-BSSEAzureCli {
    [CmdletBinding()]
    param()

    $az = Get-Command az -ErrorAction SilentlyContinue
    if (-not $az) {
        throw "Azure CLI (az) wurde nicht gefunden. Installiere Azure CLI und starte das Skript erneut."
    }

    Write-Host "[OK] Azure CLI gefunden." -ForegroundColor Green

    $ext = Invoke-BSSEAz -Arguments @('extension','show','--name','azure-devops','--only-show-errors')
    if ($ext.ExitCode -ne 0) {
        Write-Host "[AUTO] Azure-DevOps-CLI-Erweiterung fehlt und wird installiert ..." -ForegroundColor Cyan
        $install = Invoke-BSSEAz -Arguments @(
            'extension','add',
            '--name','azure-devops',
            '--only-show-errors'
        )

        if ($install.ExitCode -ne 0) {
            throw "Azure-DevOps-CLI-Erweiterung konnte nicht automatisch installiert werden.`n$($install.Output)"
        }
    }

    Write-Host "[OK] Azure-DevOps-CLI-Erweiterung verfügbar." -ForegroundColor Green
}

function Get-BSSEOrganizationProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl
    )

    $configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config\organizations.json'
    if (-not (Test-Path $configPath)) {
        return $null
    }

    try {
        $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        return @($config.organizations) |
            Where-Object {
                ($_.organizationUrl.TrimEnd('/') + '/') -eq ($OrganizationUrl.TrimEnd('/') + '/')
            } |
            Select-Object -First 1
    }
    catch {
        Write-Warning "Organisationsprofil konnte nicht gelesen werden: $($_.Exception.Message)"
        return $null
    }
}

function Get-BSSEAzureAccount {
    [CmdletBinding()]
    param()

    $result = Invoke-BSSEAz -Arguments @(
        'account','show',
        '--output','json',
        '--only-show-errors'
    )

    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return $null
    }

    try {
        return ($result.Output | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-BSSECachedAzureAccounts {
    [CmdletBinding()]
    param()

    $result = Invoke-BSSEAz -Arguments @(
        'account','list',
        '--all',
        '--output','json',
        '--only-show-errors'
    )

    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return @()
    }

    try {
        return @($result.Output | ConvertFrom-Json)
    }
    catch {
        return @()
    }
}

function Test-BSSEPipelineContext {
    [CmdletBinding()]
    param()

    return (
        $env:TF_BUILD -eq 'True' -or
        -not [string]::IsNullOrWhiteSpace($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI) -or
        -not [string]::IsNullOrWhiteSpace($env:AGENT_ID)
    )
}

function Test-BSSEAzureDevOpsCliAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl
    )

    $projectTest = Invoke-BSSEAz -Arguments @(
        'devops','project','list',
        '--org', $OrganizationUrl,
        '--top','1',
        '--output','json',
        '--only-show-errors'
    )

    return [pscustomobject]@{
        Success = ($projectTest.ExitCode -eq 0)
        Phase   = 'AzureDevOps'
        Error   = if ($projectTest.ExitCode -eq 0) { '' } else { $projectTest.Output }
    }
}

function Test-BSSEAzureDevOpsAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl
    )

    $tokenTest = Invoke-BSSEAz -Arguments @(
        'account','get-access-token',
        '--resource','499b84ac-1321-427f-aa17-267ca6975798',
        '--query','accessToken',
        '--output','tsv',
        '--only-show-errors'
    )

    if ($tokenTest.ExitCode -ne 0) {
        return [pscustomobject]@{
            Success = $false
            Phase   = 'Token'
            Error   = $tokenTest.Output
        }
    }

    return Test-BSSEAzureDevOpsCliAccess -OrganizationUrl $OrganizationUrl
}

function Set-BSSESubscriptionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SubscriptionId
    )

    $set = Invoke-BSSEAz -Arguments @(
        'account','set',
        '--subscription', $SubscriptionId
    )

    return ($set.ExitCode -eq 0)
}

function Find-BSSECachedAzureDevOpsContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [string]$PreferredTenantId
    )

    $accounts = @(Get-BSSECachedAzureAccounts)

    $candidates = @(
        $accounts |
        Where-Object {
            $_.state -eq 'Enabled' -and
            $_.id -and
            $_.name -and
            $_.name -ne 'N/A(tenant level account)'
        }
    )

    if ($PreferredTenantId) {
        $preferred = @($candidates | Where-Object { $_.tenantId -eq $PreferredTenantId })
        $other     = @($candidates | Where-Object { $_.tenantId -ne $PreferredTenantId })
        $candidates = @($preferred + $other)
    }

    $seen = @{}

    foreach ($candidate in $candidates) {
        if ($seen.ContainsKey($candidate.id)) {
            continue
        }

        $seen[$candidate.id] = $true

        if (-not (Set-BSSESubscriptionContext -SubscriptionId $candidate.id)) {
            continue
        }

        $access = Test-BSSEAzureDevOpsAccess -OrganizationUrl $OrganizationUrl

        if ($access.Success) {
            return [pscustomobject]@{
                Success = $true
                Account = Get-BSSEAzureAccount
                Access  = $access
            }
        }
    }

    return [pscustomobject]@{
        Success = $false
        Account = $null
        Access  = $null
    }
}

function Invoke-BSSEInteractiveAzureLogin {
    [CmdletBinding()]
    param(
        [string]$TenantId
    )

    Write-Host "[AUTO] Interaktive Microsoft-Anmeldung wird gestartet ..." -ForegroundColor Cyan

    if ($TenantId) {
        Write-Host "       Anmeldung wird auf den benötigten Tenant begrenzt: $TenantId" -ForegroundColor DarkGray
    }

    Write-Host "       Falls Microsoft MFA verlangt, muss nur die Anmeldung bestätigt werden." -ForegroundColor DarkGray

    $args = @('login','--allow-no-subscriptions')
    if ($TenantId) {
        $args += @('--tenant', $TenantId)
    }

    & az @args --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Interaktive Azure-Anmeldung ist fehlgeschlagen."
    }
}

function Open-BSSEAzureDevOpsBrowser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl
    )

    Write-Host "[AUTO] Azure DevOps wird zur Erstinitialisierung im Browser geöffnet." -ForegroundColor Cyan
    Write-Host "       Falls eine Anmeldung/MFA erscheint, bitte nur diese abschließen; das Skript prüft danach automatisch weiter." -ForegroundColor DarkGray

    try {
        Start-Process $OrganizationUrl | Out-Null
    }
    catch {
        Write-Warning "Browser konnte nicht automatisch geöffnet werden: $($_.Exception.Message)"
    }
}

function Wait-BSSEAzureDevOpsAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [int]$TimeoutSeconds = 180,

        [int]$PollSeconds = 3
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = $null

    do {
        $last = Test-BSSEAzureDevOpsAccess -OrganizationUrl $OrganizationUrl
        if ($last.Success) {
            return $last
        }

        Start-Sleep -Seconds $PollSeconds
    }
    while ((Get-Date) -lt $deadline)

    return $last
}

function Write-BSSEActiveAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Account
    )

    $userName = if ($Account.user -and $Account.user.name) { $Account.user.name } else { '<unbekannt>' }
    $tenantId = if ($Account.tenantId) { $Account.tenantId } else { '<unbekannt>' }
    $subName  = if ($Account.name) { $Account.name } else { '<keine Subscription>' }

    Write-Host "[OK] Azure-Anmeldung: $userName" -ForegroundColor Green
    Write-Host "     Tenant:       $tenantId" -ForegroundColor DarkGray
    Write-Host "     Subscription: $subName" -ForegroundColor DarkGray
}

function Initialize-BSSEPipelineAzureDevOpsSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl
    )

    Write-Host "[AUTO] Azure-Pipelines-Ausführung erkannt." -ForegroundColor DarkCyan
    Write-Host "       Interaktive Anmeldung und Browser-Fallbacks sind in diesem Modus deaktiviert." -ForegroundColor DarkGray

    # Preferred mode: AzureCLI@3 with an Azure DevOps service connection / Entra WIF.
    # AzureCLI@3 establishes the CLI session before this script starts.
    $directAccess = Test-BSSEAzureDevOpsCliAccess -OrganizationUrl $OrganizationUrl
    if ($directAccess.Success) {
        $account = Get-BSSEAzureAccount
        Write-Host "[OK] Pipeline-Identität kann auf Azure DevOps zugreifen." -ForegroundColor Green
        Write-Host "     Authentifizierung: Azure DevOps Service Connection / bestehende CLI-Session" -ForegroundColor DarkGray

        return [pscustomobject]@{
            OrganizationUrl    = $OrganizationUrl
            Account            = $account
            ExecutionMode      = 'Pipeline'
            AuthenticationMode = 'PipelineServiceConnection'
        }
    }

    # Compatibility fallback: YAML may explicitly map $(System.AccessToken) to SYSTEM_ACCESSTOKEN.
    # az devops automatically consumes AZURE_DEVOPS_EXT_PAT for non-interactive authentication.
    if (-not [string]::IsNullOrWhiteSpace($env:SYSTEM_ACCESSTOKEN)) {
        Write-Host "[AUTO] Keine nutzbare Service-Connection-Session erkannt; System.AccessToken ist vorhanden." -ForegroundColor Cyan
        Write-Host "[AUTO] Binde System.AccessToken prozesslokal an die Azure-DevOps-CLI." -ForegroundColor Cyan
        $env:AZURE_DEVOPS_EXT_PAT = $env:SYSTEM_ACCESSTOKEN

        $tokenAccess = Test-BSSEAzureDevOpsCliAccess -OrganizationUrl $OrganizationUrl
        if ($tokenAccess.Success) {
            Write-Host "[OK] Azure-DevOps-Zugriff über Pipeline System.AccessToken verifiziert." -ForegroundColor Green

            return [pscustomobject]@{
                OrganizationUrl    = $OrganizationUrl
                Account            = $null
                ExecutionMode      = 'Pipeline'
                AuthenticationMode = 'PipelineSystemAccessToken'
            }
        }

        throw @"
Azure Pipeline wurde erkannt und System.AccessToken wurde automatisch eingebunden,
der Zugriff auf Azure DevOps ist jedoch fehlgeschlagen.

Organisation: $OrganizationUrl
Fehler:       $($tokenAccess.Error)

Prüfe die Berechtigungen der Build-Service-/Pipeline-Identität und den Job Authorization Scope.
Der Bootstrap führt in einer Pipeline niemals einen interaktiven Login durch.
"@
    }

    throw @"
Azure Pipeline wurde erkannt, aber es steht keine funktionsfähige nicht-interaktive
Azure-DevOps-Authentifizierung zur Verfügung.

Bevorzugter Zielzustand:
- AzureCLI@3
- connectionType: azureDevOps
- Azure DevOps Service Connection mit Microsoft Entra Workload Identity Federation

Fallback:
- $(System.AccessToken) im YAML explizit als SYSTEM_ACCESSTOKEN an den Skriptschritt mappen

Der Bootstrap versucht in einer Pipeline absichtlich weder 'az login' noch einen Browser-Fallback.
"@
}

function Initialize-BSSEAzureDevOpsSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl
    )

    $org = ConvertTo-BSSEOrganizationUrl -OrganizationUrl $OrganizationUrl
    Assert-BSSEAzureCli

    $profile = Get-BSSEOrganizationProfile -OrganizationUrl $org
    $preferredTenantId = if ($profile -and $profile.tenantId) { [string]$profile.tenantId } else { $null }

    if ($preferredTenantId) {
        Write-Host "[AUTO] Organisationsprofil erkannt; Ziel-Tenant: $preferredTenantId" -ForegroundColor DarkCyan
    }

    $configure = Invoke-BSSEAz -Arguments @(
        'devops','configure',
        '--defaults', "organization=$org"
    )

    if ($configure.ExitCode -ne 0) {
        throw "Azure DevOps CLI konnte die Standardorganisation nicht konfigurieren: $($configure.Output)"
    }

    if (Test-BSSEPipelineContext) {
        return Initialize-BSSEPipelineAzureDevOpsSession -OrganizationUrl $org
    }

    Write-Host "[AUTO] Lokale Ausführung erkannt." -ForegroundColor DarkCyan

    $account = Get-BSSEAzureAccount

    if ($account) {
        $access = Test-BSSEAzureDevOpsAccess -OrganizationUrl $org

        if ($access.Success) {
            Write-BSSEActiveAccount -Account $account
            Write-Host "[OK] Azure-DevOps-Zugriff verifiziert." -ForegroundColor Green

            return [pscustomobject]@{
                OrganizationUrl    = $org
                Account            = $account
                ExecutionMode      = 'Local'
                AuthenticationMode = 'LocalAzureCli'
            }
        }
    }

    Write-Host "[AUTO] Aktueller Azure-Kontext passt nicht zur DevOps-Organisation." -ForegroundColor Yellow
    Write-Host "[AUTO] Suche automatisch nach einem bereits angemeldeten passenden Azure-Kontext ..." -ForegroundColor Cyan

    $cached = Find-BSSECachedAzureDevOpsContext `
        -OrganizationUrl $org `
        -PreferredTenantId $preferredTenantId

    if ($cached.Success) {
        Write-Host "[AUTO] Passenden Azure-Kontext im lokalen CLI-Cache gefunden." -ForegroundColor Cyan
        Write-BSSEActiveAccount -Account $cached.Account
        Write-Host "[OK] Azure-DevOps-Zugriff verifiziert." -ForegroundColor Green

        return [pscustomobject]@{
            OrganizationUrl    = $org
            Account            = $cached.Account
            ExecutionMode      = 'Local'
            AuthenticationMode = 'LocalCachedAzureCli'
        }
    }

    Write-Host "[AUTO] Kein bereits angemeldeter Kontext konnte auf Azure DevOps zugreifen." -ForegroundColor Yellow
    Invoke-BSSEInteractiveAzureLogin -TenantId $preferredTenantId

    $cached = Find-BSSECachedAzureDevOpsContext `
        -OrganizationUrl $org `
        -PreferredTenantId $preferredTenantId

    if ($cached.Success) {
        Write-BSSEActiveAccount -Account $cached.Account
        Write-Host "[OK] Azure-DevOps-Zugriff verifiziert." -ForegroundColor Green

        return [pscustomobject]@{
            OrganizationUrl    = $org
            Account            = $cached.Account
            ExecutionMode      = 'Local'
            AuthenticationMode = 'LocalInteractiveAzureCli'
        }
    }

    Open-BSSEAzureDevOpsBrowser -OrganizationUrl $org
    Write-Host "[AUTO] Warte auf erfolgreiche Azure-DevOps-Erstinitialisierung ..." -ForegroundColor Cyan
    $access = Wait-BSSEAzureDevOpsAccess -OrganizationUrl $org

    if (-not $access.Success) {
        $account = Get-BSSEAzureAccount
        $userName = if ($account -and $account.user -and $account.user.name) { $account.user.name } else { '<unbekannt>' }
        $tenantId = if ($account -and $account.tenantId) { $account.tenantId } else { '<unbekannt>' }

        throw @"
Azure DevOps konnte trotz automatischer Kontextsuche, gezieltem Tenant-Login und Browser-Bootstrap nicht geöffnet werden.

Organisation: $org
CLI-Benutzer: $userName
Tenant:       $tenantId

Letzter Azure-DevOps-Fehler:
$($access.Error)

Das Skript hat alle lokal selbstheilbaren Zustände automatisch bearbeitet.
Wenn es hier stoppt, handelt es sich sehr wahrscheinlich um fehlende Mitgliedschaft oder Berechtigung
der Identität in der Azure-DevOps-Organisation.
"@
    }

    $account = Get-BSSEAzureAccount
    Write-BSSEActiveAccount -Account $account
    Write-Host "[OK] Azure-DevOps-Zugriff verifiziert." -ForegroundColor Green

    return [pscustomobject]@{
        OrganizationUrl    = $org
        Account            = $account
        ExecutionMode      = 'Local'
        AuthenticationMode = 'LocalBrowserBootstrap'
    }
}

function Get-BSSEProjectRepositories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$Project
    )

    $json = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
        'repos','list',
        '--org', $OrganizationUrl,
        '--project', $Project,
        '--output','json',
        '--only-show-errors'
    )

    return @($json | ConvertFrom-Json)
}

function Test-BSSEProjectExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$Project
    )

    $json = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
        'devops','project','list',
        '--org', $OrganizationUrl,
        '--output','json',
        '--only-show-errors'
    )

    return @((($json | ConvertFrom-Json).value) | ForEach-Object { $_.name }) -contains $Project
}

function New-BSSEEmptyGitRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$RepositoryName
    )

    # IMPORTANT:
    # az repos create creates the repository only. This function deliberately
    # does NOT clone, push, add README, add .gitignore or create an initial commit.
    Invoke-BSSEAzDevOpsOrThrow -Arguments @(
        'repos','create',
        '--org', $OrganizationUrl,
        '--project', $Project,
        '--name', $RepositoryName,
        '--only-show-errors'
    ) | Out-Null
}
