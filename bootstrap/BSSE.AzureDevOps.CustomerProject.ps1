Set-StrictMode -Version Latest

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
