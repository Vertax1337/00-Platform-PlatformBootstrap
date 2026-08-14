Set-StrictMode -Version Latest

# Azure DevOps project creation is asynchronous. In the real BSSE-CloudOps runtime on
# 2026-08-14, `az devops project create` returned VS800075 even though the server had
# already created the project and subsequently made it readable. Customer onboarding
# therefore treats VS800075 from this one command as a bounded materialization race.
# All other Azure CLI calls retain the common fail-closed behavior unchanged.
$script:BSSECustomerProjectCreateRecoveryAttempts = 20
$script:BSSECustomerProjectCreateRecoveryDelaySeconds = 3

if (-not (Get-Variable -Name BSSEInvokeAzCore -Scope Script -ErrorAction SilentlyContinue)) {
    $script:BSSEInvokeAzCore = ${function:Invoke-BSSEAz}
}

function Invoke-BSSEAz {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$PassThruOutput
    )

    $result = & $script:BSSEInvokeAzCore `
        -Arguments $Arguments `
        -PassThruOutput:$PassThruOutput

    if ($result.ExitCode -eq 0) {
        return $result
    }

    $isProjectCreate = (
        $Arguments.Count -ge 3 -and
        $Arguments[0] -eq 'devops' -and
        $Arguments[1] -eq 'project' -and
        $Arguments[2] -eq 'create'
    )

    if (-not $isProjectCreate -or $result.Output -notmatch 'VS800075') {
        return $result
    }

    $orgIndex = [array]::IndexOf($Arguments, '--org')
    $nameIndex = [array]::IndexOf($Arguments, '--name')

    if (
        $orgIndex -lt 0 -or $orgIndex + 1 -ge $Arguments.Count -or
        $nameIndex -lt 0 -or $nameIndex + 1 -ge $Arguments.Count
    ) {
        return $result
    }

    $organizationUrl = [string]$Arguments[$orgIndex + 1]
    $projectName = [string]$Arguments[$nameIndex + 1]
    $attempts = [int]$script:BSSECustomerProjectCreateRecoveryAttempts
    $delaySeconds = [int]$script:BSSECustomerProjectCreateRecoveryDelaySeconds

    Write-Host "[WAIT] Project create returned VS800075 for '$projectName'. Waiting for asynchronous Azure DevOps materialization ..." -ForegroundColor Yellow

    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $show = & $script:BSSEInvokeAzCore -Arguments @(
            'devops','project','show',
            '--org', $organizationUrl,
            '--project', $projectName,
            '--output','json',
            '--only-show-errors'
        )

        if ($show.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($show.Output)) {
            try {
                $project = $show.Output | ConvertFrom-Json
            }
            catch {
                $project = $null
            }

            if ($project -and $project.name -and $project.name.Equals($projectName, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "[RECOVER] Project '$projectName' became readable after async create materialization (attempt $attempt/$attempts). Continuing the same onboarding run." -ForegroundColor DarkCyan
                return [pscustomobject]@{
                    ExitCode = 0
                    Output   = $show.Output
                }
            }
        }

        if ($attempt -lt $attempts -and $delaySeconds -gt 0) {
            Start-Sleep -Seconds $delaySeconds
        }
    }

    $waitSeconds = [Math]::Max(0, ($attempts - 1) * $delaySeconds)
    Write-Host "[BLOCKED] Project create returned VS800075 and '$projectName' did not become readable within approximately $waitSeconds seconds." -ForegroundColor Red
    return $result
}

function Get-BSSEAzureDevOpsProjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [ValidateRange(1,1000)]
        [int]$PageSize = 500
    )

    $projects = @()
    $skip = 0

    while ($true) {
        $result = Invoke-BSSEAz -Arguments @(
            'devops','project','list',
            '--org', $OrganizationUrl,
            '--state-filter','wellFormed',
            '--top', ([string]$PageSize),
            '--skip', ([string]$skip),
            '--output','json',
            '--only-show-errors'
        )

        if ($result.ExitCode -ne 0) {
            throw "Azure-DevOps-Projektliste konnte nicht gelesen werden (skip=$skip, top=$PageSize).`n$($result.Output)"
        }

        try {
            $json = $result.Output | ConvertFrom-Json
        }
        catch {
            throw "Azure-DevOps-Projektliste enthält kein gültiges JSON (skip=$skip)."
        }

        $page = if ($json.PSObject.Properties.Name -contains 'value') {
            @($json.value)
        }
        else {
            @($json)
        }

        $projects += $page

        if ($page.Count -lt $PageSize) {
            break
        }

        $skip += $PageSize
        if ($skip -gt 10000) {
            throw 'Azure-DevOps-Projektliste überschreitet das Sicherheitslimit von 10000 Projekten.'
        }
    }

    return @($projects)
}

function Get-BSSEAzureDevOpsProjectDirect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [ValidateRange(1,10)]
        [int]$Attempts = 1,

        [ValidateRange(0,30)]
        [int]$DelaySeconds = 2
    )

    $lastError = ''

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $result = Invoke-BSSEAz -Arguments @(
            'devops','project','show',
            '--org', $OrganizationUrl,
            '--project', $ProjectName,
            '--output','json',
            '--only-show-errors'
        )

        if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.Output)) {
            try {
                $project = $result.Output | ConvertFrom-Json
                if ($project.name) {
                    return [pscustomobject]@{
                        Found   = $true
                        Project = $project
                        Error   = ''
                    }
                }
            }
            catch {
                $lastError = "Direkt-Lookup für '$ProjectName' lieferte ungültiges JSON."
            }
        }
        else {
            $lastError = $result.Output
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return [pscustomobject]@{
        Found   = $false
        Project = $null
        Error   = $lastError
    }
}

function Resolve-BSSECustomerProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$CustomerNumber,

        [Parameter(Mandatory)]
        [string]$RequestedProjectName,

        [ValidateRange(1,10)]
        [int]$DirectLookupAttempts = 1
    )

    $customerPrefix = "CUST-$CustomerNumber-"
    $candidates = @()

    # First resolve the exact desired name. This is deliberately independent from
    # project-list paging and is the primary recovery path for partially completed runs.
    $direct = Get-BSSEAzureDevOpsProjectDirect `
        -OrganizationUrl $OrganizationUrl `
        -ProjectName $RequestedProjectName `
        -Attempts $DirectLookupAttempts

    if ($direct.Found) {
        $candidates += [string]$direct.Project.name
    }

    # CustomerNumber remains the stable identity across company-name/slug changes.
    # Read every visible well-formed project page instead of trusting the first CLI page.
    $projects = @(Get-BSSEAzureDevOpsProjects -OrganizationUrl $OrganizationUrl)
    $candidates += @(
        $projects |
            ForEach-Object { [string]$_.name } |
            Where-Object {
                $_ -and $_.StartsWith($customerPrefix, [System.StringComparison]::OrdinalIgnoreCase)
            }
    )

    $unique = @(
        $candidates |
            Group-Object { $_.ToLowerInvariant() } |
            ForEach-Object { [string]$_.Group[0] }
    )

    if ($unique.Count -gt 1) {
        throw "Mehrere Azure-DevOps-Projekte verwenden dieselbe CustomerNumber '$CustomerNumber': $($unique -join ', '). Die Kunden-ID muss eindeutig sein."
    }

    if ($unique.Count -eq 1) {
        $projectName = $unique[0]
        if (-not $projectName.StartsWith($customerPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Aufgelöstes Kundenprojekt '$projectName' passt nicht zur erwarteten CustomerNumber '$CustomerNumber'."
        }

        return [pscustomobject]@{
            Exists        = $true
            ProjectName   = $projectName
            EffectiveSlug = $projectName.Substring($customerPrefix.Length)
            RequestedName = $RequestedProjectName
            Source        = if ($direct.Found -and $projectName.Equals([string]$direct.Project.name, [System.StringComparison]::OrdinalIgnoreCase)) { 'DirectLookup' } else { 'CustomerNumberSearch' }
        }
    }

    return [pscustomobject]@{
        Exists        = $false
        ProjectName   = $RequestedProjectName
        EffectiveSlug = $RequestedProjectName.Substring($customerPrefix.Length)
        RequestedName = $RequestedProjectName
        Source        = 'NotFound'
    }
}

function Assert-BSSECustomerProjectReadable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$ProjectName
    )

    $direct = Get-BSSEAzureDevOpsProjectDirect `
        -OrganizationUrl $OrganizationUrl `
        -ProjectName $ProjectName `
        -Attempts 3

    if (-not $direct.Found) {
        Write-Host "[BLOCKED] Project '$ProjectName' exists or was just created, but the bootstrap identity cannot resolve it directly." -ForegroundColor Red
        throw @"
Customer project '$ProjectName' ist nicht belastbar lesbar.

Der Bootstrap versucht deshalb NICHT, ein gleichnamiges Projekt erneut anzulegen.
Prüfe den projektbezogenen Zugriff der ausführenden Azure-DevOps-Identität sowie einen eventuell noch laufenden Create-Vorgang.

Letzter Direkt-Lookup-Fehler:
$($direct.Error)
"@
    }

    return $direct.Project
}
