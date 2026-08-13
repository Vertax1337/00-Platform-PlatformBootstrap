[CmdletBinding()]
param(
    [string]$OrganizationUrl = 'https://dev.azure.com/BSSE-CloudOps/',
    [string]$Project = '00-Platform',
    [string]$Repository = 'PlatformBootstrap',
    [string]$IdentityName = 'sp-bsse-platform-bootstrap-azdo',
    [string]$ServiceConnectionName = 'sc-platform-bootstrap-azdo',
    [string]$PipelineName = 'Customer-Onboarding',
    [string]$YamlPath = 'pipelines/customer-onboarding.yml',
    [string]$TenantId,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"

if ($Apply -and (Test-BSSEPipelineContext)) {
    throw @"
Initialize-BSSEPlatformDependencies.ps1 darf Plattform-Dependencies nur aus einer
lokalen, bewusst privilegierten Erstinitialisierung heraus verändern.

Eine Azure Pipeline darf sich ihre eigene Entra-Identität oder organisationsweiten
Azure-DevOps-Rechte nicht selbst geben. In Pipelines ist nur Dry Run / Verify zulässig.
"@
}

function Get-BSSEOrganizationName {
    param([Parameter(Mandatory)][string]$Url)

    $uri = [uri]$Url
    $segments = @($uri.AbsolutePath.Trim('/') -split '/')
    if (-not $segments.Count -or [string]::IsNullOrWhiteSpace($segments[0])) {
        throw "Azure-DevOps-Organisationsname konnte aus '$Url' nicht ermittelt werden."
    }

    return [string]$segments[0]
}

function Get-BSSEDevOpsAccessToken {
    $result = Invoke-BSSEAz -Arguments @(
        'account','get-access-token',
        '--resource','499b84ac-1321-427f-aa17-267ca6975798',
        '--query','accessToken',
        '--output','tsv',
        '--only-show-errors'
    )

    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        throw "Azure-DevOps-Entra-Zugriffstoken konnte nicht bezogen werden.`n$($result.Output)"
    }

    return $result.Output.Trim()
}

function Invoke-BSSEDevOpsRest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH','PUT','DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        $Body
    )

    $invoke = @{
        Uri         = $Url
        Method      = $Method
        Headers     = @{ Authorization = "Bearer $(Get-BSSEDevOpsAccessToken)" }
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $invoke.ContentType = 'application/json'
        $invoke.Body = ($Body | ConvertTo-Json -Depth 40 -Compress)
    }

    return Invoke-RestMethod @invoke
}

function Get-BSSEProjectInfo {
    param([Parameter(Mandatory)][string]$ProjectName)

    $result = Invoke-BSSEAz -Arguments @(
        'devops','project','show',
        '--org',$OrganizationUrl,
        '--project',$ProjectName,
        '--output','json',
        '--only-show-errors'
    )

    if ($result.ExitCode -ne 0) {
        return $null
    }

    return ($result.Output | ConvertFrom-Json)
}

function Get-BSSEEntraIdentityState {
    param([Parameter(Mandatory)][string]$DisplayName)

    $spResult = Invoke-BSSEAz -Arguments @(
        'ad','sp','list',
        '--display-name',$DisplayName,
        '--output','json',
        '--only-show-errors'
    )
    if ($spResult.ExitCode -ne 0) {
        throw "Entra Service Principals konnten nicht gelesen werden.`n$($spResult.Output)"
    }

    $principals = @(@($spResult.Output | ConvertFrom-Json) |
        Where-Object { $_.displayName -eq $DisplayName })

    if ($principals.Count -gt 1) {
        throw "Mehrere Entra Service Principals heißen exakt '$DisplayName'. Eindeutige Plattformidentität erforderlich."
    }

    $appResult = Invoke-BSSEAz -Arguments @(
        'ad','app','list',
        '--display-name',$DisplayName,
        '--output','json',
        '--only-show-errors'
    )
    if ($appResult.ExitCode -ne 0) {
        throw "Entra App Registrations konnten nicht gelesen werden.`n$($appResult.Output)"
    }

    $applications = @(@($appResult.Output | ConvertFrom-Json) |
        Where-Object { $_.displayName -eq $DisplayName })

    if ($applications.Count -gt 1) {
        throw "Mehrere Entra App Registrations heißen exakt '$DisplayName'. Eindeutige Plattformidentität erforderlich."
    }

    return [pscustomobject]@{
        ServicePrincipal = if ($principals.Count -eq 1) { $principals[0] } else { $null }
        Application      = if ($applications.Count -eq 1) { $applications[0] } else { $null }
    }
}

function Wait-BSSEEntraServicePrincipal {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [int]$Attempts = 10,
        [int]$DelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $state = Get-BSSEEntraIdentityState -DisplayName $DisplayName
        if ($state.ServicePrincipal) {
            return $state.ServicePrincipal
        }
        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $null
}

function Ensure-BSSEEntraIdentity {
    param([Parameter(Mandatory)][string]$DisplayName)

    $state = Get-BSSEEntraIdentityState -DisplayName $DisplayName

    if ($state.ServicePrincipal) {
        Write-Host "[EXISTS] Entra service principal $DisplayName" -ForegroundColor DarkGray
        return $state.ServicePrincipal
    }

    if (-not $Apply) {
        if ($state.Application) {
            Write-Host "[PLAN] Materialize service principal for existing Entra app $DisplayName" -ForegroundColor Yellow
            return [pscustomobject]@{
                appId       = $state.Application.appId
                id          = $null
                displayName = $DisplayName
            }
        }

        Write-Host "[PLAN] Create passwordless Entra app/service principal $DisplayName" -ForegroundColor Yellow
        return [pscustomobject]@{
            appId       = $null
            id          = $null
            displayName = $DisplayName
        }
    }

    if ($state.Application) {
        Write-Host "[CREATE] Service principal for existing Entra app $DisplayName" -ForegroundColor Green
        $create = Invoke-BSSEAz -Arguments @(
            'ad','sp','create',
            '--id',$state.Application.appId,
            '--output','json',
            '--only-show-errors'
        )
    }
    else {
        Write-Host "[CREATE] Passwordless Entra app/service principal $DisplayName" -ForegroundColor Green
        $create = Invoke-BSSEAz -Arguments @(
            'ad','sp','create-for-rbac',
            '--name',$DisplayName,
            '--create-password','false',
            '--output','json',
            '--only-show-errors'
        )
    }

    if ($create.ExitCode -ne 0) {
        throw @"
Entra-Identität '$DisplayName' konnte nicht automatisch erstellt werden.

Fehler:
$($create.Output)

Der angemeldete Erstinstallations-Administrator benötigt die Entra-Berechtigung,
eine App Registration / einen Service Principal anzulegen. Der Bootstrap eskaliert
diese Berechtigung nicht selbst.
"@
    }

    $servicePrincipal = Wait-BSSEEntraServicePrincipal -DisplayName $DisplayName
    if (-not $servicePrincipal) {
        throw "Entra service principal '$DisplayName' wurde nach der Erstellung nicht rechtzeitig wiedergefunden."
    }

    Write-Host "[OK] Entra service principal $DisplayName erstellt." -ForegroundColor Green
    return $servicePrincipal
}

function Get-BSSEAzureDevOpsGraphServicePrincipals {
    param([Parameter(Mandatory)][string]$OrganizationName)

    $all = @()
    $continuation = $null

    do {
        $url = "https://vssps.dev.azure.com/$OrganizationName/_apis/graph/serviceprincipals?api-version=7.1-preview.1"
        if ($continuation) {
            $url += "&continuationToken=$([uri]::EscapeDataString($continuation))"
        }

        $response = Invoke-WebRequest `
            -Uri $url `
            -Headers @{ Authorization = "Bearer $(Get-BSSEDevOpsAccessToken)" } `
            -Method GET `
            -ErrorAction Stop

        $body = $response.Content | ConvertFrom-Json
        $all += @($body.value)

        $continuation = $null
        foreach ($key in @('X-MS-ContinuationToken','x-ms-continuationtoken')) {
            if ($response.Headers[$key]) {
                $continuation = [string]$response.Headers[$key]
                break
            }
        }
    }
    while ($continuation)

    return @($all)
}

function Wait-BSSEAzureDevOpsGraphServicePrincipal {
    param(
        [Parameter(Mandatory)][string]$OrganizationName,
        [Parameter(Mandatory)][string]$OriginId,
        [int]$Attempts = 10,
        [int]$DelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $matches = @(@(Get-BSSEAzureDevOpsGraphServicePrincipals -OrganizationName $OrganizationName) |
            Where-Object { $_.originId -eq $OriginId })

        if ($matches.Count -gt 1) {
            throw "Azure DevOps enthält mehrere Graph-Service-Principals für Entra objectId $OriginId."
        }
        if ($matches.Count -eq 1) {
            return $matches[0]
        }
        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $null
}

function Ensure-BSSEAzureDevOpsEntitlement {
    param(
        [AllowNull()]$EntraServicePrincipal,
        [Parameter(Mandatory)]$ProjectInfo,
        [Parameter(Mandatory)][string]$OrganizationName
    )

    if (-not $EntraServicePrincipal -or -not $EntraServicePrincipal.id) {
        Write-Host "[PLAN] Add $IdentityName to Azure DevOps: Basic + $Project/Readers" -ForegroundColor Yellow
        return $null
    }

    $graphPrincipal = Wait-BSSEAzureDevOpsGraphServicePrincipal `
        -OrganizationName $OrganizationName `
        -OriginId $EntraServicePrincipal.id `
        -Attempts 1

    if (-not $graphPrincipal) {
        if (-not $Apply) {
            Write-Host "[PLAN] Add $IdentityName to Azure DevOps: Basic + $Project/Readers" -ForegroundColor Yellow
            return $null
        }

        Write-Host "[CREATE] Azure DevOps entitlement: Basic + $Project/Readers" -ForegroundColor Green
        $body = @{
            accessLevel = @{
                accountLicenseType = 'express'
                licensingSource    = 'account'
            }
            projectEntitlements = @(
                @{
                    group = @{ groupType = 'projectReader' }
                    projectRef = @{ id = $ProjectInfo.id }
                }
            )
            servicePrincipal = @{
                origin      = 'aad'
                originId    = $EntraServicePrincipal.id
                subjectKind = 'servicePrincipal'
            }
        }

        $url = "https://vsaex.dev.azure.com/$OrganizationName/_apis/serviceprincipalentitlements?api-version=7.1-preview.1"
        $maxAttempts = 6
        $delaySeconds = 5
        $response = $null

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            $response = Invoke-BSSEDevOpsRest -Method POST -Url $url -Body $body

            $operationFailed = (
                ($response.operationResult -and $response.operationResult.isSuccess -eq $false) -or
                ($response.PSObject.Properties['isSuccess'] -and $response.isSuccess -eq $false)
            )

            if (-not $operationFailed) {
                break
            }

            $transientMaterializationFailure = @($response.operationResult.errors | Where-Object {
                [int]$_.key -eq 5000 -and ([string]$_.value -match 'VS403283')
            }).Count -gt 0

            if (-not $transientMaterializationFailure -or $attempt -eq $maxAttempts) {
                throw "Azure DevOps service-principal entitlement konnte nicht angelegt werden: $($response | ConvertTo-Json -Depth 20)"
            }

            Write-Host "[WAIT] Azure DevOps hat den neuen Entra Service Principal noch nicht materialisiert (VS403283). Retry $attempt/$maxAttempts ..." -ForegroundColor Yellow
            Start-Sleep -Seconds $delaySeconds

            $graphPrincipal = Wait-BSSEAzureDevOpsGraphServicePrincipal `
                -OrganizationName $OrganizationName `
                -OriginId $EntraServicePrincipal.id `
                -Attempts 1

            if ($graphPrincipal) {
                break
            }
        }

        if (-not $graphPrincipal) {
            $graphPrincipal = Wait-BSSEAzureDevOpsGraphServicePrincipal `
                -OrganizationName $OrganizationName `
                -OriginId $EntraServicePrincipal.id
        }

        if (-not $graphPrincipal) {
            throw "Azure DevOps service principal wurde nach Entitlement-Erstellung nicht rechtzeitig wiedergefunden."
        }
    }

    $storageUrl = "https://vssps.dev.azure.com/$OrganizationName/_apis/graph/storagekeys/$([uri]::EscapeDataString($graphPrincipal.descriptor))?api-version=7.1"
    $storage = Invoke-BSSEDevOpsRest -Method GET -Url $storageUrl
    if (-not $storage.value) {
        throw "Azure DevOps storage key für $IdentityName konnte nicht ermittelt werden."
    }

    $entitlementUrl = "https://vsaex.dev.azure.com/$OrganizationName/_apis/serviceprincipalentitlements/$($storage.value)?api-version=7.1-preview.1"
    $entitlement = Invoke-BSSEDevOpsRest -Method GET -Url $entitlementUrl

    $basicOk = ($entitlement.accessLevel.accountLicenseType -eq 'express')
    $readerOk = @($entitlement.projectEntitlements | Where-Object {
        $_.projectRef.id -eq $ProjectInfo.id -and $_.group.groupType -eq 'projectReader'
    }).Count -gt 0

    if (-not $basicOk -or -not $readerOk) {
        Write-Host "[BLOCKED] Existing Azure DevOps entitlement for $IdentityName differs from required Basic + $Project/Readers." -ForegroundColor Red
        throw "Bestehende Plattformidentität wird nicht automatisch auf eine andere Lizenz/Projektrolle umgeschrieben."
    }

    Write-Host "[EXISTS] Azure DevOps entitlement: Basic + $Project/Readers" -ForegroundColor DarkGray
    return $graphPrincipal
}

function Get-BSSECollectionCreateProjectsMetadata {
    $result = Invoke-BSSEAz -Arguments @(
        'devops','security','permission','namespace','list',
        '--org',$OrganizationUrl,
        '--output','json',
        '--only-show-errors'
    )
    if ($result.ExitCode -ne 0) {
        throw "Azure DevOps security namespaces konnten nicht gelesen werden.`n$($result.Output)"
    }

    $collection = @($result.Output | ConvertFrom-Json) |
        Where-Object { $_.name -eq 'Collection' } |
        Select-Object -First 1

    if (-not $collection) {
        throw "Azure DevOps security namespace 'Collection' wurde nicht gefunden."
    }

    $action = @($collection.actions | Where-Object { $_.name -eq 'CREATE_PROJECTS' }) |
        Select-Object -First 1

    if (-not $action) {
        throw "Collection permission action CREATE_PROJECTS wurde nicht gefunden."
    }

    return [pscustomobject]@{
        NamespaceId = [string]$collection.namespaceId
        Bit         = [int64]$action.bit
    }
}

function ConvertFrom-BSSEPermissionListOutput {
    param(
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][string]$Subject
    )

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return @()
    }

    try {
        $items = @($Output | ConvertFrom-Json)
    }
    catch {
        throw "Azure-DevOps-Berechtigungsausgabe konnte nicht als JSON gelesen werden: $($_.Exception.Message)"
    }

    $records = @()
    foreach ($item in $items) {
        if (-not $item.PSObject.Properties['token'] -or [string]::IsNullOrWhiteSpace([string]$item.token)) {
            throw "Azure-DevOps-Berechtigungsausgabe enthält ein ACL-Objekt ohne Token. Fail Closed statt Ausgabeformat zu raten."
        }

        [int64]$effectiveAllow = 0
        [int64]$effectiveDeny = 0
        $resolved = $false

        # Some CLI versions/formatters expose flattened Effective Allow/Deny values.
        if ($item.PSObject.Properties['effectiveAllow'] -or $item.PSObject.Properties['effectiveDeny']) {
            if ($item.PSObject.Properties['effectiveAllow']) {
                $effectiveAllow = [int64]$item.effectiveAllow
            }
            if ($item.PSObject.Properties['effectiveDeny']) {
                $effectiveDeny = [int64]$item.effectiveDeny
            }
            $resolved = $true
        }
        elseif ($item.PSObject.Properties['acesDictionary']) {
            # The documented JSON shape is an ACL with acesDictionary; effective values live
            # under AccessControlEntry.extendedInfo. The CLI has already filtered by --subject.
            if ($null -eq $item.acesDictionary) {
                $resolved = $true
            }
            else {
                $aceProperties = @($item.acesDictionary.PSObject.Properties)
                if ($aceProperties.Count -eq 0) {
                    $resolved = $true
                }
                else {
                    $aceProperty = $aceProperties | Where-Object { $_.Name -eq $Subject } | Select-Object -First 1

                    if (-not $aceProperty) {
                        $descriptorMatches = @($aceProperties | Where-Object {
                            $_.Value -and $_.Value.PSObject.Properties['descriptor'] -and ([string]$_.Value.descriptor -eq $Subject)
                        })

                        if ($descriptorMatches.Count -eq 1) {
                            $aceProperty = $descriptorMatches[0]
                        }
                        elseif ($aceProperties.Count -eq 1) {
                            # --subject may have been an email/UPN while the dictionary key is the
                            # resolved Azure DevOps identity descriptor. A single returned ACE is unambiguous.
                            $aceProperty = $aceProperties[0]
                        }
                        else {
                            throw "Azure-DevOps-ACL für Token '$($item.token)' enthält mehrere ACEs, aber keiner ist dem Subject '$Subject' eindeutig zuordenbar."
                        }
                    }

                    $ace = $aceProperty.Value
                    if (-not $ace -or -not $ace.PSObject.Properties['extendedInfo']) {
                        throw "Azure-DevOps-ACL für Token '$($item.token)' enthält keine extendedInfo für die effektive Berechtigungsprüfung."
                    }

                    if ($ace.extendedInfo -and $ace.extendedInfo.PSObject.Properties['effectiveAllow']) {
                        $effectiveAllow = [int64]$ace.extendedInfo.effectiveAllow
                    }
                    if ($ace.extendedInfo -and $ace.extendedInfo.PSObject.Properties['effectiveDeny']) {
                        $effectiveDeny = [int64]$ace.extendedInfo.effectiveDeny
                    }
                    $resolved = $true
                }
            }
        }

        if (-not $resolved) {
            throw "Unbekanntes Azure-DevOps-Berechtigungsausgabeformat für Token '$($item.token)'. Fail Closed statt Berechtigungen zu raten."
        }

        $records += [pscustomobject]@{
            Token          = [string]$item.token
            EffectiveAllow = $effectiveAllow
            EffectiveDeny  = $effectiveDeny
        }
    }

    return @($records)
}

function Get-BSSERootCollectionTokenFromAdministrator {
    param(
        [Parameter(Mandatory)][string]$NamespaceId,
        [Parameter(Mandatory)][int64]$CreateProjectsBit,
        [Parameter(Mandatory)][string]$AdministratorSubject
    )

    $result = Invoke-BSSEAz -Arguments @(
        'devops','security','permission','list',
        '--org',$OrganizationUrl,
        '--id',$NamespaceId,
        '--subject',$AdministratorSubject,
        '--output','json',
        '--only-show-errors'
    )
    if ($result.ExitCode -ne 0) {
        throw "Collection security tokens konnten für '$AdministratorSubject' nicht gelesen werden.`n$($result.Output)"
    }

    $records = @(ConvertFrom-BSSEPermissionListOutput -Output $result.Output -Subject $AdministratorSubject)
    $candidates = @($records | Where-Object {
        $_.Token -and
        (([int64]$_.EffectiveAllow -band $CreateProjectsBit) -eq $CreateProjectsBit) -and
        (([int64]$_.EffectiveDeny -band $CreateProjectsBit) -eq 0)
    } | Sort-Object { ([string]$_.Token).Length })

    if (-not $candidates.Count) {
        throw @"
Der aktuell angemeldete Erstinstallations-Administrator besitzt keinen auffindbaren
Collection-ACL-Token mit effektiver CREATE_PROJECTS-Berechtigung.

Der Bootstrap rät den Collection-Root-Token nicht. Verwende für die Erstinitialisierung
einen Organisationsadministrator, der 'Create new projects' vergeben darf.
"@
    }

    return [string]$candidates[0].Token
}

function Get-BSSEPermissionState {
    param(
        [Parameter(Mandatory)][string]$NamespaceId,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Token
    )

    $result = Invoke-BSSEAz -Arguments @(
        'devops','security','permission','list',
        '--org',$OrganizationUrl,
        '--id',$NamespaceId,
        '--subject',$Subject,
        '--token',$Token,
        '--output','json',
        '--only-show-errors'
    )

    if ($result.ExitCode -ne 0) {
        return $null
    }

    $records = @(ConvertFrom-BSSEPermissionListOutput -Output $result.Output -Subject $Subject)
    $matches = @($records | Where-Object { $_.Token -eq $Token })
    if ($matches.Count -gt 1) {
        throw "Azure DevOps lieferte mehrere Berechtigungszustände für Token '$Token' und Subject '$Subject'."
    }

    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function Ensure-BSSECreateProjectsPermission {
    param(
        $GraphPrincipal,
        [Parameter(Mandatory)]$Session
    )

    if (-not $GraphPrincipal) {
        Write-Host "[PLAN] Grant collection permission: Create new projects = Allow" -ForegroundColor Yellow
        return
    }

    $metadata = Get-BSSECollectionCreateProjectsMetadata
    if (-not $Session.Account -or -not $Session.Account.user -or [string]::IsNullOrWhiteSpace($Session.Account.user.name)) {
        throw "Aktueller lokaler Administrator konnte für die sichere Collection-Token-Ermittlung nicht bestimmt werden."
    }

    $adminSubject = [string]$Session.Account.user.name
    $rootToken = Get-BSSERootCollectionTokenFromAdministrator `
        -NamespaceId $metadata.NamespaceId `
        -CreateProjectsBit $metadata.Bit `
        -AdministratorSubject $adminSubject

    $state = Get-BSSEPermissionState `
        -NamespaceId $metadata.NamespaceId `
        -Subject $GraphPrincipal.descriptor `
        -Token $rootToken

    if ($state -and (([int64]$state.EffectiveDeny -band $metadata.Bit) -eq $metadata.Bit)) {
        Write-Host "[BLOCKED] Create new projects is explicitly/effectively denied for $IdentityName." -ForegroundColor Red
        throw "Ein vorhandenes Deny wird vom Bootstrap nicht automatisch überschrieben."
    }

    if ($state -and (([int64]$state.EffectiveAllow -band $metadata.Bit) -eq $metadata.Bit)) {
        Write-Host "[EXISTS] Collection permission: Create new projects = Allow" -ForegroundColor DarkGray
        return
    }

    if (-not $Apply) {
        Write-Host "[PLAN] Grant collection permission: Create new projects = Allow" -ForegroundColor Yellow
        return
    }

    Write-Host "[GRANT] Collection permission: Create new projects = Allow" -ForegroundColor Green
    $update = Invoke-BSSEAz -Arguments @(
        'devops','security','permission','update',
        '--org',$OrganizationUrl,
        '--id',$metadata.NamespaceId,
        '--subject',$GraphPrincipal.descriptor,
        '--token',$rootToken,
        '--allow-bit',([string]$metadata.Bit),
        '--merge','true',
        '--output','json',
        '--only-show-errors'
    )
    if ($update.ExitCode -ne 0) {
        throw "Create new projects konnte nicht vergeben werden.`n$($update.Output)"
    }

    $state = Get-BSSEPermissionState `
        -NamespaceId $metadata.NamespaceId `
        -Subject $GraphPrincipal.descriptor `
        -Token $rootToken

    if (-not $state -or
        (([int64]$state.EffectiveAllow -band $metadata.Bit) -ne $metadata.Bit) -or
        (([int64]$state.EffectiveDeny -band $metadata.Bit) -eq $metadata.Bit)) {
        throw "Create new projects konnte nach der Vergabe nicht verifiziert werden."
    }

    Write-Host "[OK] Create new projects für $IdentityName verifiziert." -ForegroundColor Green
}

function Invoke-BSSEGitWithBearer {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$BearerToken,
        [string]$WorkingDirectory
    )

    $oldCount = $env:GIT_CONFIG_COUNT
    $oldKey0 = $env:GIT_CONFIG_KEY_0
    $oldValue0 = $env:GIT_CONFIG_VALUE_0
    $oldLocation = Get-Location

    try {
        $env:GIT_CONFIG_COUNT = '1'
        $env:GIT_CONFIG_KEY_0 = 'http.extraHeader'
        $env:GIT_CONFIG_VALUE_0 = "Authorization: Bearer $BearerToken"

        if ($WorkingDirectory) {
            Set-Location $WorkingDirectory
        }

        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Git command failed: git $($Arguments -join ' ')`n$(($output | Out-String).Trim())"
        }

        return (($output | Out-String).Trim())
    }
    finally {
        Set-Location $oldLocation
        $env:GIT_CONFIG_COUNT = $oldCount
        $env:GIT_CONFIG_KEY_0 = $oldKey0
        $env:GIT_CONFIG_VALUE_0 = $oldValue0
    }
}

function Ensure-BSSEPlatformBootstrapRepositorySeeded {
    param([Parameter(Mandatory)]$Repo)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git wurde nicht gefunden. Die Erstinitialisierung kann PlatformBootstrap nicht sicher nach Azure Repos übertragen."
    }

    $localRoot = Split-Path $PSScriptRoot -Parent

    $rootOutput = & git -C $localRoot rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Lokales PlatformBootstrap-Repository konnte nicht bestimmt werden: $(($rootOutput | Out-String).Trim())"
    }
    $repoRoot = (($rootOutput | Select-Object -First 1) | Out-String).Trim()

    $dirtyOutput = & git -C $repoRoot status --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Lokaler Git-Status konnte nicht gelesen werden."
    }
    if (-not [string]::IsNullOrWhiteSpace(($dirtyOutput | Out-String))) {
        Write-Host '[BLOCKED] Local PlatformBootstrap working tree contains uncommitted changes.' -ForegroundColor Red
        throw "Erstinitialisierung verwendet ausschließlich einen committed Source-of-Truth. Committe oder verwerfe lokale Änderungen zuerst."
    }

    $headOutput = & git -C $repoRoot rev-parse HEAD 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Lokaler PlatformBootstrap-Commit konnte nicht bestimmt werden."
    }
    $localHead = (($headOutput | Select-Object -First 1) | Out-String).Trim()

    $refsResult = Invoke-BSSEAz -Arguments @(
        'repos','ref','list',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--repository',$Repository,
        '--output','json',
        '--only-show-errors'
    )
    if ($refsResult.ExitCode -ne 0) {
        throw "Azure-Repo-Refs konnten nicht gelesen werden.`n$($refsResult.Output)"
    }

    $refs = @($refsResult.Output | ConvertFrom-Json)
    $mainRef = $refs | Where-Object { $_.name -eq 'refs/heads/main' } | Select-Object -First 1

    if ($refs.Count -eq 0) {
        if (-not $Apply) {
            Write-Host "[PLAN] Seed empty $Project/$Repository from local committed HEAD $localHead" -ForegroundColor Yellow
            return
        }

        Write-Host "[PUBLISH] Seed empty $Project/$Repository from local committed HEAD" -ForegroundColor Green
        $token = Get-BSSEDevOpsAccessToken
        Invoke-BSSEGitWithBearer `
            -BearerToken $token `
            -WorkingDirectory $repoRoot `
            -Arguments @('push',$Repo.remoteUrl,'HEAD:refs/heads/main') | Out-Null

        $refsResult = Invoke-BSSEAz -Arguments @(
            'repos','ref','list',
            '--org',$OrganizationUrl,
            '--project',$Project,
            '--repository',$Repository,
            '--output','json',
            '--only-show-errors'
        )
        if ($refsResult.ExitCode -ne 0) {
            throw "Azure-Repo-Refs konnten nach Seed nicht gelesen werden.`n$($refsResult.Output)"
        }

        $refs = @($refsResult.Output | ConvertFrom-Json)
        $mainRef = $refs | Where-Object { $_.name -eq 'refs/heads/main' } | Select-Object -First 1
        if (-not $mainRef -or $mainRef.objectId -ne $localHead) {
            throw "PlatformBootstrap main wurde nach dem Seed nicht mit lokalem HEAD verifiziert."
        }

        Write-Host "[OK] PlatformBootstrap Azure Repo seeded at $localHead" -ForegroundColor Green
        return
    }

    if (-not $mainRef) {
        Write-Host "[BLOCKED] $Project/$Repository is non-empty but has no refs/heads/main." -ForegroundColor Red
        throw "Ein nicht-leeres PlatformBootstrap-Repository wird nicht automatisch überschrieben oder umgeschrieben."
    }

    if ($mainRef.objectId -ne $localHead) {
        Write-Host '[BLOCKED] Azure PlatformBootstrap main differs from local committed HEAD.' -ForegroundColor Red
        Write-Host "          Azure: $($mainRef.objectId)" -ForegroundColor DarkGray
        Write-Host "          Local: $localHead" -ForegroundColor DarkGray
        throw "Source-of-Truth-Divergenz. Kein automatischer Force-Push."
    }

    Write-Host "[EXISTS] $Project/$Repository main matches local committed HEAD $localHead" -ForegroundColor DarkGray
}

function Resolve-BSSEEndpointInputValue {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$OrganizationName,
        [Parameter(Mandatory)][string]$Tenant,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$PrincipalId
    )

    switch -Regex ($Id.ToLowerInvariant()) {
        '^(tenantid|tenant)$' { return $Tenant }
        '^(serviceprincipalid|clientid|appid|applicationid)$' { return $AppId }
        '^(serviceprincipalobjectid|principalid|objectid|identityid)$' { return $PrincipalId }
        '^(organization|organizationname|accountname)$' { return $OrganizationName }
        '^(organizationurl|targetorganizationurl|targeturl)$' { return $OrganizationUrl.TrimEnd('/') }
        '^(creationmode)$' { return 'Manual' }
        default { return $null }
    }
}

function Get-BSSEAzureDevOpsServiceEndpointType {
    $url = "$($OrganizationUrl.TrimEnd('/'))/_apis/serviceendpoint/types?api-version=7.1"
    $response = Invoke-BSSEDevOpsRest -Method GET -Url $url
    $types = @($response.value)

    $candidates = @($types | Where-Object {
        $_.displayName -eq 'Azure DevOps' -and
        @($_.authenticationSchemes | Where-Object { $_.scheme -eq 'WorkloadIdentityFederation' }).Count -gt 0
    })

    if ($candidates.Count -ne 1) {
        throw @"
Der Azure-DevOps-Service-Connection-Typ mit WorkloadIdentityFederation wurde in dieser
Organisation nicht eindeutig gefunden.

Gefundene Kandidaten: $($candidates.Count)

Der Bootstrap verwendet absichtlich keinen undokumentierten hartcodierten Endpoint-Typ.
Prüfe beim ersten Runtime-Lauf die von Azure DevOps gelieferten Endpoint-Type-Metadaten.
"@
    }

    return $candidates[0]
}

function New-BSSEServiceEndpointConfiguration {
    param(
        [Parameter(Mandatory)]$EndpointType,
        [Parameter(Mandatory)]$ProjectInfo,
        [Parameter(Mandatory)]$EntraServicePrincipal,
        [Parameter(Mandatory)][string]$OrganizationName,
        [Parameter(Mandatory)][string]$Tenant
    )

    $scheme = @($EndpointType.authenticationSchemes | Where-Object {
        $_.scheme -eq 'WorkloadIdentityFederation'
    }) | Select-Object -First 1

    if (-not $scheme) {
        throw "WIF-Authentifizierungsschema fehlt im Azure-DevOps-Endpoint-Type."
    }

    $data = @{ creationMode = 'Manual' }
    $authParameters = @{
        tenantid           = $Tenant
        serviceprincipalid = $EntraServicePrincipal.appId
    }

    foreach ($descriptor in @($EndpointType.inputDescriptors)) {
        $value = Resolve-BSSEEndpointInputValue `
            -Id $descriptor.id `
            -OrganizationName $OrganizationName `
            -Tenant $Tenant `
            -AppId $EntraServicePrincipal.appId `
            -PrincipalId $EntraServicePrincipal.id

        if ($null -ne $value) {
            $data[$descriptor.id] = $value
        }
        elseif ($descriptor.validation -and $descriptor.validation.isRequired) {
            throw "Unbekanntes erforderliches Azure-DevOps-Service-Endpoint-Input '$($descriptor.id)'. Fail Closed statt Schema zu raten."
        }
    }

    foreach ($descriptor in @($scheme.inputDescriptors)) {
        $value = Resolve-BSSEEndpointInputValue `
            -Id $descriptor.id `
            -OrganizationName $OrganizationName `
            -Tenant $Tenant `
            -AppId $EntraServicePrincipal.appId `
            -PrincipalId $EntraServicePrincipal.id

        if ($null -ne $value) {
            $authParameters[$descriptor.id] = $value
        }
        elseif ($descriptor.validation -and $descriptor.validation.isRequired) {
            throw "Unbekanntes erforderliches WIF-Authorization-Input '$($descriptor.id)'. Fail Closed statt Schema zu raten."
        }
    }

    return @{
        data = $data
        name = $ServiceConnectionName
        type = $EndpointType.name
        url  = $OrganizationUrl.TrimEnd('/')
        authorization = @{
            parameters = $authParameters
            scheme     = 'WorkloadIdentityFederation'
        }
        isShared = $false
        isReady  = $true
        description = 'BSSE PlatformBootstrap - secretless Azure DevOps provisioning identity.'
        serviceEndpointProjectReferences = @(
            @{
                projectReference = @{
                    id   = $ProjectInfo.id
                    name = $ProjectInfo.name
                }
                name = $ServiceConnectionName
            }
        )
    }
}

function Get-BSSEServiceConnection {
    $result = Invoke-BSSEAz -Arguments @(
        'devops','service-endpoint','list',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--output','json',
        '--only-show-errors'
    )
    if ($result.ExitCode -ne 0) {
        throw "Service Connections konnten nicht gelesen werden.`n$($result.Output)"
    }

    $matches = @(@($result.Output | ConvertFrom-Json) | Where-Object {
        $_.name -eq $ServiceConnectionName
    })

    if ($matches.Count -gt 1) {
        throw "Mehrere Service Connections heißen '$ServiceConnectionName'."
    }

    if ($matches.Count -eq 0) {
        return $null
    }

    $show = Invoke-BSSEAz -Arguments @(
        'devops','service-endpoint','show',
        '--id',$matches[0].id,
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--output','json',
        '--only-show-errors'
    )
    if ($show.ExitCode -ne 0) {
        throw "Service Connection '$ServiceConnectionName' konnte nicht vollständig gelesen werden.`n$($show.Output)"
    }

    return ($show.Output | ConvertFrom-Json)
}

function Ensure-BSSEServiceConnection {
    param(
        [Parameter(Mandatory)]$ProjectInfo,
        [Parameter(Mandatory)]$EntraServicePrincipal,
        [Parameter(Mandatory)][string]$OrganizationName,
        [Parameter(Mandatory)][string]$Tenant
    )

    $endpoint = Get-BSSEServiceConnection
    if ($endpoint) {
        if ($endpoint.authorization.scheme -ne 'WorkloadIdentityFederation') {
            Write-Host "[BLOCKED] Existing $ServiceConnectionName is not WorkloadIdentityFederation." -ForegroundColor Red
            throw "Bestehende Service Connection wird nicht automatisch ersetzt."
        }

        $configuredAppId = [string]$endpoint.authorization.parameters.serviceprincipalid
        if ($configuredAppId -and $configuredAppId -ne $EntraServicePrincipal.appId) {
            Write-Host "[BLOCKED] Existing $ServiceConnectionName points to another Entra application." -ForegroundColor Red
            throw "Bestehende Service Connection wird nicht automatisch umgebogen."
        }

        Write-Host "[EXISTS] Service Connection $ServiceConnectionName (WIF)" -ForegroundColor DarkGray
        return $endpoint
    }

    $endpointType = Get-BSSEAzureDevOpsServiceEndpointType

    if (-not $Apply) {
        Write-Host "[PLAN] Create Azure DevOps WIF Service Connection $ServiceConnectionName" -ForegroundColor Yellow
        Write-Host "[PLAN] Create federated credential after Service Connection yields issuer/subject" -ForegroundColor Yellow
        return $null
    }

    $configuration = New-BSSEServiceEndpointConfiguration `
        -EndpointType $endpointType `
        -ProjectInfo $ProjectInfo `
        -EntraServicePrincipal $EntraServicePrincipal `
        -OrganizationName $OrganizationName `
        -Tenant $Tenant

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("bsse-service-endpoint-" + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $configuration | ConvertTo-Json -Depth 40 | Set-Content -Path $temp -Encoding utf8

        Write-Host "[CREATE] Service Connection $ServiceConnectionName" -ForegroundColor Green
        $create = Invoke-BSSEAz -Arguments @(
            'devops','service-endpoint','create',
            '--service-endpoint-configuration',$temp,
            '--org',$OrganizationUrl,
            '--project',$Project,
            '--output','json',
            '--only-show-errors'
        )

        if ($create.ExitCode -ne 0) {
            throw @"
Azure DevOps WIF Service Connection konnte mit dem zur Laufzeit ermittelten Endpoint-Schema
nicht erstellt werden.

$($create.Output)

Es wird bewusst kein alternativer oder undokumentierter Endpoint-Typ geraten.
"@
        }
    }
    finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    }

    $endpoint = Get-BSSEServiceConnection
    if (-not $endpoint) {
        throw "Service Connection '$ServiceConnectionName' wurde nach Create nicht wiedergefunden."
    }

    Write-Host "[OK] Service Connection $ServiceConnectionName erstellt." -ForegroundColor Green
    return $endpoint
}

function Ensure-BSSEFederatedCredential {
    param(
        [Parameter(Mandatory)]$EntraServicePrincipal,
        $ServiceConnection
    )

    if (-not $ServiceConnection) {
        if (-not $Apply) {
            return
        }
        throw "Federated Credential kann ohne Service Connection nicht erstellt werden."
    }

    $issuer = [string]$ServiceConnection.authorization.parameters.workloadIdentityFederationIssuer
    $subject = [string]$ServiceConnection.authorization.parameters.workloadIdentityFederationSubject

    if ([string]::IsNullOrWhiteSpace($issuer) -or [string]::IsNullOrWhiteSpace($subject)) {
        Write-Host '[BLOCKED] Service Connection exposes no WIF issuer/subject.' -ForegroundColor Red
        throw "Federated Credential kann ohne vom Service Endpoint erzeugten issuer/subject nicht sicher erstellt werden."
    }

    $ficName = "fic-$ServiceConnectionName"
    $list = Invoke-BSSEAz -Arguments @(
        'ad','app','federated-credential','list',
        '--id',$EntraServicePrincipal.appId,
        '--output','json',
        '--only-show-errors'
    )
    if ($list.ExitCode -ne 0) {
        throw "Federated Credentials konnten nicht gelesen werden.`n$($list.Output)"
    }

    $matches = @(@($list.Output | ConvertFrom-Json) | Where-Object { $_.name -eq $ficName })
    if ($matches.Count -gt 1) {
        throw "Mehrere federated credentials heißen '$ficName'."
    }

    if ($matches.Count -eq 1) {
        $fic = $matches[0]
        $audienceOk = @($fic.audiences) -contains 'api://AzureADTokenExchange'

        if ($fic.issuer -ne $issuer -or $fic.subject -ne $subject -or -not $audienceOk) {
            Write-Host "[BLOCKED] Existing federated credential $ficName differs from Service Connection." -ForegroundColor Red
            throw "Federated Credential wird nicht automatisch ersetzt."
        }

        Write-Host "[EXISTS] Federated credential $ficName" -ForegroundColor DarkGray
        return
    }

    if (-not $Apply) {
        Write-Host "[PLAN] Create federated credential $ficName" -ForegroundColor Yellow
        return
    }

    $parameters = @{
        name      = $ficName
        issuer    = $issuer
        subject   = $subject
        audiences = @('api://AzureADTokenExchange')
    }

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("bsse-fic-" + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $parameters | ConvertTo-Json -Depth 10 | Set-Content -Path $temp -Encoding utf8

        Write-Host "[CREATE] Federated credential $ficName" -ForegroundColor Green
        $create = Invoke-BSSEAz -Arguments @(
            'ad','app','federated-credential','create',
            '--id',$EntraServicePrincipal.appId,
            '--parameters',$temp,
            '--output','none',
            '--only-show-errors'
        )

        if ($create.ExitCode -ne 0) {
            throw "Federated Credential konnte nicht erstellt werden.`n$($create.Output)"
        }
    }
    finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[OK] Federated credential $ficName erstellt." -ForegroundColor Green
}

function Ensure-BSSEPipelineRegistrationAndAuthorization {
    param($ServiceConnection)

    if (-not $ServiceConnection) {
        Write-Host "[PLAN] Register $PipelineName and authorize only this pipeline for $ServiceConnectionName" -ForegroundColor Yellow
        return
    }

    $registerParams = @{
        OrganizationUrl       = $OrganizationUrl
        Project               = $Project
        Repository            = $Repository
        PipelineName          = $PipelineName
        YamlPath              = $YamlPath
        ServiceConnectionName = $ServiceConnectionName
    }
    if ($Apply) {
        $registerParams.Apply = $true
    }

    & "$PSScriptRoot\Register-BSSECustomerOnboardingPipeline.ps1" @registerParams

    $pipelinesResult = Invoke-BSSEAz -Arguments @(
        'pipelines','list',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--output','json',
        '--only-show-errors'
    )
    if ($pipelinesResult.ExitCode -ne 0) {
        throw "Pipelines konnten nach Registrierung nicht gelesen werden.`n$($pipelinesResult.Output)"
    }

    $pipeline = @($pipelinesResult.Output | ConvertFrom-Json) |
        Where-Object { $_.name -eq $PipelineName } |
        Select-Object -First 1

    if (-not $pipeline) {
        if (-not $Apply) {
            Write-Host "[PLAN] Authorize $PipelineName for Service Connection after pipeline registration" -ForegroundColor Yellow
            return
        }
        throw "Pipeline '$PipelineName' wurde nicht gefunden."
    }

    $url = "$($OrganizationUrl.TrimEnd('/'))/$Project/_apis/pipelines/pipelinepermissions/endpoint/$($ServiceConnection.id)?api-version=7.1-preview.1"
    $state = $null
    try {
        $state = Invoke-BSSEDevOpsRest -Method GET -Url $url
    }
    catch {
        $state = $null
    }

    $authorized = $false
    if ($state) {
        $authorized = @($state.pipelines | Where-Object {
            $_.id -eq $pipeline.id -and $_.authorized
        }).Count -gt 0
    }

    if ($authorized) {
        Write-Host "[EXISTS] $PipelineName authorized for $ServiceConnectionName" -ForegroundColor DarkGray
        return
    }

    if (-not $Apply) {
        Write-Host "[PLAN] Authorize only $PipelineName for $ServiceConnectionName" -ForegroundColor Yellow
        return
    }

    Write-Host "[GRANT] Pipeline-specific use of $ServiceConnectionName to $PipelineName" -ForegroundColor Green
    $body = @{
        pipelines = @(
            @{
                id         = [int]$pipeline.id
                authorized = $true
            }
        )
    }
    Invoke-BSSEDevOpsRest -Method PATCH -Url $url -Body $body | Out-Null

    $state = Invoke-BSSEDevOpsRest -Method GET -Url $url
    $authorized = @($state.pipelines | Where-Object {
        $_.id -eq $pipeline.id -and $_.authorized
    }).Count -gt 0

    if (-not $authorized) {
        throw "Pipeline-specific Service-Connection-Autorisierung konnte nicht verifiziert werden."
    }

    Write-Host "[OK] $PipelineName ist gezielt für $ServiceConnectionName autorisiert." -ForegroundColor Green
}

Write-Host ''
Write-Host 'BSSE Platform Dependencies / Self-Hosting Bootstrap' -ForegroundColor Cyan
Write-Host "Organization:       $OrganizationUrl"
Write-Host "Project:            $Project"
Write-Host "Identity:           $IdentityName"
Write-Host "Service Connection: $ServiceConnectionName"
Write-Host "Pipeline:           $PipelineName"
Write-Host "Mode:               $(if ($Apply) { 'APPLY' } else { 'DRY RUN / VERIFY' })"
Write-Host ''

$session = Initialize-BSSEAzureDevOpsSession -OrganizationUrl $OrganizationUrl
$OrganizationUrl = $session.OrganizationUrl
$organizationName = Get-BSSEOrganizationName -Url $OrganizationUrl

if ([string]::IsNullOrWhiteSpace($TenantId)) {
    $profile = Get-BSSEOrganizationProfile -OrganizationUrl $OrganizationUrl
    if ($profile -and $profile.tenantId) {
        $TenantId = [string]$profile.tenantId
    }
}

if ([string]::IsNullOrWhiteSpace($TenantId)) {
    throw "TenantId konnte weder explizit noch aus config/organizations.json bestimmt werden."
}

$currentAccount = Get-BSSEAzureAccount
if (-not $currentAccount -or $currentAccount.tenantId -ne $TenantId) {
    if (Test-BSSEPipelineContext) {
        throw "Pipeline-Azure-Kontext ist nicht im erwarteten Tenant $TenantId."
    }

    Write-Host "[AUTO] Wechsle für die Plattform-Erstinitialisierung gezielt in Tenant $TenantId." -ForegroundColor Cyan
    Invoke-BSSEInteractiveAzureLogin -TenantId $TenantId
    $currentAccount = Get-BSSEAzureAccount
}

if (-not $currentAccount -or $currentAccount.tenantId -ne $TenantId) {
    throw "Aktiver Azure-CLI-Tenant ist nicht der erwartete Plattform-Tenant $TenantId."
}
Write-Host "[OK] Platform tenant context: $TenantId" -ForegroundColor Green

Write-Host ''
Write-Host 'Core platform topology:' -ForegroundColor Cyan
$coreParams = @{
    OrganizationUrl = $OrganizationUrl
}
if ($Apply) {
    $coreParams.Apply = $true
}
& "$PSScriptRoot\New-BSSEAzureDevOpsCore.ps1" @coreParams

$projectInfo = Get-BSSEProjectInfo -ProjectName $Project
if (-not $projectInfo) {
    if (-not $Apply) {
        Write-Host "[PLAN] After core creation: seed $Project/$Repository" -ForegroundColor Yellow
        Write-Host "[PLAN] After core creation: create/configure $IdentityName" -ForegroundColor Yellow
        Write-Host "[PLAN] After core creation: create WIF Service Connection $ServiceConnectionName" -ForegroundColor Yellow
        Write-Host "[PLAN] After core creation: register/authorize $PipelineName" -ForegroundColor Yellow
        return
    }

    throw "Projekt '$Project' fehlt nach Core-Apply."
}

$repos = @(Get-BSSEProjectRepositories -OrganizationUrl $OrganizationUrl -Project $Project)
$repo = $repos | Where-Object { $_.name -eq $Repository } | Select-Object -First 1
if (-not $repo) {
    if (-not $Apply) {
        Write-Host "[PLAN] Remaining dependencies require $Project/$Repository." -ForegroundColor Yellow
        return
    }

    throw "Repository '$Project/$Repository' fehlt nach Core-Apply."
}

Write-Host ''
Write-Host 'PlatformBootstrap execution source:' -ForegroundColor Cyan
Ensure-BSSEPlatformBootstrapRepositorySeeded -Repo $repo

Write-Host ''
Write-Host 'Entra / Azure DevOps platform identity:' -ForegroundColor Cyan
$entraSp = Ensure-BSSEEntraIdentity -DisplayName $IdentityName
$graphSp = Ensure-BSSEAzureDevOpsEntitlement `
    -EntraServicePrincipal $entraSp `
    -ProjectInfo $projectInfo `
    -OrganizationName $organizationName

Ensure-BSSECreateProjectsPermission -GraphPrincipal $graphSp -Session $session

Write-Host ''
Write-Host 'Secretless Azure DevOps Service Connection:' -ForegroundColor Cyan
if (-not $entraSp.id) {
    Write-Host "[PLAN] Create $ServiceConnectionName after Entra identity exists" -ForegroundColor Yellow
    Write-Host "[PLAN] Create federated credential after Service Connection yields issuer/subject" -ForegroundColor Yellow
    Write-Host "[PLAN] Register/authorize $PipelineName after Service Connection exists" -ForegroundColor Yellow
    return
}

$serviceConnection = Ensure-BSSEServiceConnection `
    -ProjectInfo $projectInfo `
    -EntraServicePrincipal $entraSp `
    -OrganizationName $organizationName `
    -Tenant $TenantId

Ensure-BSSEFederatedCredential `
    -EntraServicePrincipal $entraSp `
    -ServiceConnection $serviceConnection

Ensure-BSSEPipelineRegistrationAndAuthorization -ServiceConnection $serviceConnection

Write-Host ''
if ($Apply) {
    Write-Host '[OK] Platform dependencies configured and verified without Project Collection Administrator membership.' -ForegroundColor Green
}
else {
    Write-Host '[OK] Platform dependency dry run / verification completed.' -ForegroundColor Cyan
}
