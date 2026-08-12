[CmdletBinding()]
param(
    [string]$OrganizationUrl = 'https://dev.azure.com/BSSE-CloudOps/'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"

if (Test-BSSEPipelineContext) {
    throw @"
Start-BSSECustomerOnboarding.ps1 ist das interaktive lokale Frontend.
In Azure Pipelines wird stattdessen /pipelines/customer-onboarding.yml verwendet.
Beide Wege rufen dieselben Backend-/Persistenzskripte auf.
"@
}

function Read-BSSERequiredValue {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [scriptblock]$Validator,
        [string]$ValidationMessage = 'Ungültige Eingabe.'
    )

    while ($true) {
        $value = (Read-Host $Prompt).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host '  Eingabe ist erforderlich.' -ForegroundColor Yellow
            continue
        }

        if ($Validator -and -not (& $Validator $value)) {
            Write-Host "  $ValidationMessage" -ForegroundColor Yellow
            continue
        }

        return $value
    }
}

function Read-BSSEOptionalValue {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [scriptblock]$Validator,
        [string]$ValidationMessage = 'Ungültige Eingabe.'
    )

    while ($true) {
        $value = (Read-Host $Prompt).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            return ''
        }

        if ($Validator -and -not (& $Validator $value)) {
            Write-Host "  $ValidationMessage" -ForegroundColor Yellow
            continue
        }

        return $value
    }
}

function Read-BSSEYesNo {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $false
    )

    $suffix = if ($Default) { '[J/n]' } else { '[j/N]' }

    while ($true) {
        $answer = (Read-Host "$Prompt $suffix").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }

        switch -Regex ($answer) {
            '^(j|ja|y|yes)$' { return $true }
            '^(n|nein|no)$'  { return $false }
            default {
                Write-Host '  Bitte J/Ja oder N/Nein eingeben.' -ForegroundColor Yellow
            }
        }
    }
}

function Get-BSSEOnboardingArguments {
    param(
        [Parameter(Mandatory)][hashtable]$Parameters,
        [switch]$Apply
    )

    $arguments = @(
        '-OrganizationUrl', $Parameters.OrganizationUrl,
        '-CustomerNumber', $Parameters.CustomerNumber,
        '-CustomerName', $Parameters.CustomerName
    )

    if (-not [string]::IsNullOrWhiteSpace($Parameters.CustomerSlug)) {
        $arguments += @('-CustomerSlug', $Parameters.CustomerSlug)
    }

    if (-not [string]::IsNullOrWhiteSpace($Parameters.TenantId)) {
        $arguments += @('-TenantId', $Parameters.TenantId)
    }

    if ($Parameters.Modules.Count -gt 0) {
        $arguments += @('-Modules', ($Parameters.Modules -join ','))
    }

    if (-not [string]::IsNullOrWhiteSpace($Parameters.Firewalls)) {
        $arguments += @('-Firewalls', $Parameters.Firewalls)
    }

    if ($Apply) {
        $arguments += '-Apply'
    }

    return @($arguments)
}

function Invoke-BSSECustomerOnboardingBackend {
    param(
        [Parameter(Mandatory)][hashtable]$Parameters,
        [switch]$Apply
    )

    $arguments = Get-BSSEOnboardingArguments -Parameters $Parameters -Apply:$Apply
    return @(& "$PSScriptRoot\New-BSSECustomerProject.ps1" @arguments *>&1)
}

function Invoke-BSSECustomerConfigurationSync {
    param(
        [Parameter(Mandatory)][hashtable]$Parameters,
        [switch]$Apply
    )

    $arguments = Get-BSSEOnboardingArguments -Parameters $Parameters -Apply:$Apply
    return @(& "$PSScriptRoot\Sync-BSSECustomerConfiguration.ps1" @arguments *>&1)
}

Write-Host ''
Write-Host 'BSSE Customer Onboarding - Local Technician Frontend' -ForegroundColor Cyan
Write-Host 'Dasselbe Backend und dieselbe CustomerConfiguration-Persistenz wie die Azure-DevOps-Pipeline.' -ForegroundColor DarkGray
Write-Host ''

$customerNumber = Read-BSSERequiredValue `
    -Prompt 'Customer / Debitor number' `
    -Validator { param($v) $v -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$' } `
    -ValidationMessage 'Erlaubt sind 1-32 Zeichen: Buchstaben, Zahlen, Punkt, Unterstrich und Bindestrich.'

$customerName = Read-BSSERequiredValue -Prompt 'Customer name'

$customerSlug = Read-BSSEOptionalValue `
    -Prompt 'Customer slug (optional, Enter = automatisch aus Customer name)' `
    -Validator { param($v) $v -match '^[A-Za-z0-9][A-Za-z0-9-]{0,63}$' } `
    -ValidationMessage 'Der optionale Slug darf nur Buchstaben, Zahlen und Bindestriche enthalten.'

$tenantId = Read-BSSEOptionalValue `
    -Prompt 'Azure Tenant ID (optional)' `
    -Validator {
        param($v)
        $parsed = [guid]::Empty
        [guid]::TryParse($v, [ref]$parsed)
    } `
    -ValidationMessage 'Tenant ID muss eine gültige GUID sein.'

$azureDocumentation = Read-BSSEYesNo -Prompt 'AzureDocumentation aktivieren?' -Default $true
$opnsenseDocumentation = Read-BSSEYesNo -Prompt 'OPNsenseDocumentation aktivieren?' -Default $false

Write-Host ''
Write-Host 'Hinweis: Firewall-Repositories sind vom OPNsenseDocumentation-Modul entkoppelt.' -ForegroundColor DarkGray
$firewalls = Read-BSSEOptionalValue -Prompt 'Firewalls / sites (kommasepariert, optional)'

$modules = @()
if ($azureDocumentation) {
    $modules += 'AzureDocumentation'
}
if ($opnsenseDocumentation) {
    $modules += 'OPNsenseDocumentation'
}

$parameters = @{
    OrganizationUrl = $OrganizationUrl
    CustomerNumber  = $customerNumber
    CustomerName    = $customerName
    CustomerSlug    = $customerSlug
    TenantId        = $tenantId
    Modules         = $modules
    Firewalls       = $firewalls
}

Write-Host ''
Write-Host 'Eingaben:' -ForegroundColor Cyan
Write-Host "  CustomerNumber:        $customerNumber"
Write-Host "  CustomerName:          $customerName"
Write-Host "  CustomerSlug:          $(if ($customerSlug) { $customerSlug } else { '<auto>' })"
Write-Host "  TenantId:              $(if ($tenantId) { $tenantId } else { '<not specified>' })"
Write-Host "  AzureDocumentation:    $azureDocumentation"
Write-Host "  OPNsenseDocumentation: $opnsenseDocumentation"
Write-Host "  Firewalls:             $(if ($firewalls) { $firewalls } else { '<none>' })"
Write-Host ''

Write-Host '=== DRY RUN: CUSTOMER BOUNDARY ===' -ForegroundColor Cyan
$dryRunOutput = Invoke-BSSECustomerOnboardingBackend -Parameters $parameters
$dryRunOutput | ForEach-Object { Write-Host $_ }

Write-Host ''
Write-Host '=== DRY RUN: CUSTOMERCONFIGURATION ===' -ForegroundColor Cyan
$configDryRunOutput = Invoke-BSSECustomerConfigurationSync -Parameters $parameters
$configDryRunOutput | ForEach-Object { Write-Host $_ }

$dryRunText = (($dryRunOutput + $configDryRunOutput) | Out-String)

if ($dryRunText -match '\[BLOCKED\]') {
    Write-Host ''
    Write-Host '[STOP] Dry Run enthält einen BLOCKED-Zustand. Apply wird nicht angeboten.' -ForegroundColor Red
    exit 2
}

if ($dryRunText -notmatch '\[PLAN\]') {
    Write-Host ''
    Write-Host '[OK] Der gewünschte Zustand einschließlich CustomerConfiguration ist bereits vorhanden. Kein Apply erforderlich.' -ForegroundColor Green
    exit 0
}

Write-Host ''
if (-not (Read-BSSEYesNo -Prompt 'Dry Run vollständig geprüft. Genau diesen Plan jetzt anwenden?' -Default $false)) {
    Write-Host 'Abgebrochen. Es wurden keine Änderungen angewendet.' -ForegroundColor Cyan
    exit 0
}

Write-Host ''
Write-Host '=== APPLY: CUSTOMER BOUNDARY ===' -ForegroundColor Cyan
$applyOutput = Invoke-BSSECustomerOnboardingBackend -Parameters $parameters -Apply
$applyOutput | ForEach-Object { Write-Host $_ }

Write-Host ''
Write-Host '=== APPLY: CUSTOMERCONFIGURATION ===' -ForegroundColor Cyan
$configApplyOutput = Invoke-BSSECustomerConfigurationSync -Parameters $parameters -Apply
$configApplyOutput | ForEach-Object { Write-Host $_ }

Write-Host ''
Write-Host '=== POST-APPLY VERIFY: CUSTOMER BOUNDARY ===' -ForegroundColor Cyan
$verifyOutput = Invoke-BSSECustomerOnboardingBackend -Parameters $parameters
$verifyOutput | ForEach-Object { Write-Host $_ }

Write-Host ''
Write-Host '=== POST-APPLY VERIFY: CUSTOMERCONFIGURATION ===' -ForegroundColor Cyan
$configVerifyOutput = Invoke-BSSECustomerConfigurationSync -Parameters $parameters
$configVerifyOutput | ForEach-Object { Write-Host $_ }

$verifyText = (($verifyOutput + $configVerifyOutput) | Out-String)

if ($verifyText -match '\[(PLAN|CREATE|RENAME|BLOCKED)\]') {
    throw 'Post-Apply-Verifikation hat einen ausstehenden oder blockierten Zustand gefunden. Der Sollzustand ist nicht idempotent.'
}

Write-Host ''
Write-Host '[OK] Customer-Onboarding einschließlich persistenter CustomerConfiguration abgeschlossen und idempotent verifiziert.' -ForegroundColor Green
