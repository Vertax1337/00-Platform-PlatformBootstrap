Set-StrictMode -Version Latest

# Project branding is a managed PlatformBootstrap desired state.
# Azure DevOps Core currently documents Set/Remove Project Avatar, but no Project-Avatar GET.
# To avoid an unconditional avatar write on every bootstrap run, PlatformBootstrap stores the
# SHA-256 of the successfully applied source asset as a project property. A matching marker
# means no write is required. External/manual avatar drift cannot be detected reliably while
# this marker remains unchanged; this limitation is documented in docs/Project-Branding.md.

$script:BSSEProjectAvatarHashProperty = 'BSSE.PlatformBootstrap.ProjectAvatarSha256'

function Get-BSSEProjectAvatarAssetRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )

    switch ($ProjectName.ToLowerInvariant()) {
        '00-platform'   { return 'assets/project-icons/00-platform.png' }
        '10-automation' { return 'assets/project-icons/10-automation.png' }
        '20-iac'        { return 'assets/project-icons/20-iac.png' }
        '30-idd'        { return 'assets/project-icons/30-idd.png' }
        '99-lab'        { return 'assets/project-icons/99-lab.png' }
    }

    if ($ProjectName.StartsWith('CUST-', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'assets/project-icons/cust-generic.png'
    }

    return $null
}

function Get-BSSEProjectAvatarAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )

    $relativePath = Get-BSSEProjectAvatarAssetRelativePath -ProjectName $ProjectName
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        Write-Host "[BLOCKED] No managed project-avatar mapping exists for '$ProjectName'." -ForegroundColor Red
        throw "Project '$ProjectName' is not part of the managed PlatformBootstrap branding map."
    }

    $repoRoot = Split-Path $PSScriptRoot -Parent
    $assetPath = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)

    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
        Write-Host "[BLOCKED] Branding asset missing: $relativePath" -ForegroundColor Red
        throw "Required project-branding asset '$relativePath' does not exist."
    }

    $bytes = [System.IO.File]::ReadAllBytes($assetPath)
    if ($bytes.Length -lt 8) {
        Write-Host "[BLOCKED] Branding asset is not a valid PNG: $relativePath" -ForegroundColor Red
        throw "Project-branding asset '$relativePath' is too small to be a valid PNG."
    }

    [byte[]]$pngSignature = @(0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A)
    for ($i = 0; $i -lt $pngSignature.Length; $i++) {
        if ($bytes[$i] -ne $pngSignature[$i]) {
            Write-Host "[BLOCKED] Branding asset has an invalid PNG signature: $relativePath" -ForegroundColor Red
            throw "Project-branding asset '$relativePath' is not a valid PNG file."
        }
    }

    $hash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()

    return [pscustomobject]@{
        ProjectName  = $ProjectName
        RelativePath = $relativePath
        FullPath     = $assetPath
        Sha256       = $hash
        Length       = $bytes.Length
    }
}

function Get-BSSEProjectBrandingRestToken {
    [CmdletBinding()]
    param()

    # Compatibility path for pipelines that explicitly map System.AccessToken.
    if (-not [string]::IsNullOrWhiteSpace($env:SYSTEM_ACCESSTOKEN)) {
        return $env:SYSTEM_ACCESSTOKEN
    }

    # Local execution and the preferred AzureCLI@3 / Entra-WIF pipeline path both use
    # an Entra access token for Azure DevOps.
    $token = Invoke-BSSEAz -Arguments @(
        'account','get-access-token',
        '--resource','499b84ac-1321-427f-aa17-267ca6975798',
        '--query','accessToken',
        '--output','tsv',
        '--only-show-errors'
    )

    if ($token.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($token.Output)) {
        Write-Host '[BLOCKED] Azure DevOps REST token could not be acquired for project branding.' -ForegroundColor Red
        throw "Azure-DevOps-REST-Token für Project Branding konnte nicht bezogen werden.`n$($token.Output)"
    }

    return $token.Output.Trim()
}

function Invoke-BSSEProjectBrandingRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET','PUT','PATCH')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Url,

        [string]$Body,

        [string]$ContentType = 'application/json'
    )

    $invoke = @{
        Uri         = $Url
        Method      = $Method
        Headers     = @{ Authorization = "Bearer $(Get-BSSEProjectBrandingRestToken)" }
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $invoke.Body = $Body
        $invoke.ContentType = $ContentType
    }

    try {
        $response = Invoke-WebRequest @invoke
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Content    = [string]$response.Content
        }
    }
    catch {
        $status = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = $null }
        }

        $statusText = if ($null -ne $status) { "HTTP $status" } else { 'no HTTP status' }
        Write-Host "[BLOCKED] Azure DevOps Project Branding REST call failed ($Method, $statusText)." -ForegroundColor Red
        throw "Project-Branding REST-Aufruf fehlgeschlagen: $Method $Url`n$($_.Exception.Message)"
    }
}

function Get-BSSEProjectForBranding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [int]$Attempts = 1,

        [int]$DelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $result = Invoke-BSSEAz -Arguments @(
            'devops','project','show',
            '--org',$OrganizationUrl,
            '--project',$ProjectName,
            '--output','json',
            '--only-show-errors'
        )

        if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.Output)) {
            $project = $result.Output | ConvertFrom-Json
            if ($project.id) {
                return $project
            }
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $null
}

function Get-BSSEProjectAvatarHashMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$ProjectId
    )

    $encodedKey = [uri]::EscapeDataString($script:BSSEProjectAvatarHashProperty)
    $url = "$($OrganizationUrl.TrimEnd('/'))/_apis/projects/$ProjectId/properties?keys=$encodedKey&api-version=7.1-preview.1"
    $response = Invoke-BSSEProjectBrandingRest -Method GET -Url $url

    if ($response.StatusCode -ne 200) {
        Write-Host "[BLOCKED] Project branding marker read returned HTTP $($response.StatusCode)." -ForegroundColor Red
        throw "Project-Branding-Marker konnte nicht gelesen werden (HTTP $($response.StatusCode))."
    }

    if ([string]::IsNullOrWhiteSpace($response.Content)) {
        return $null
    }

    $json = $response.Content | ConvertFrom-Json
    $property = @($json.value | Where-Object {
        $_.name -eq $script:BSSEProjectAvatarHashProperty
    }) | Select-Object -First 1

    if (-not $property) {
        return $null
    }

    return [string]$property.value
}

function Set-BSSEProjectAvatarHashMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$ProjectId,

        [Parameter(Mandatory)]
        [string]$Sha256
    )

    $url = "$($OrganizationUrl.TrimEnd('/'))/_apis/projects/$ProjectId/properties?api-version=7.1-preview.1"

    # Azure DevOps expects a JsonPatchDocument, i.e. a JSON array even when there is
    # only one patch operation. Passing a one-element PowerShell array through the
    # pipeline enumerates it before ConvertTo-Json and would serialize only the object.
    # Use -InputObject so the array itself is serialized as [ { ... } ].
    $patchDocument = @(
        [ordered]@{
            op    = 'add'
            path  = "/$($script:BSSEProjectAvatarHashProperty)"
            value = $Sha256
        }
    )
    $body = ConvertTo-Json -InputObject $patchDocument -Depth 5 -Compress

    if (-not $body.TrimStart().StartsWith('[')) {
        throw 'Project-Branding JSON-Patch konnte nicht als Array serialisiert werden.'
    }

    $response = Invoke-BSSEProjectBrandingRest `
        -Method PATCH `
        -Url $url `
        -Body $body `
        -ContentType 'application/json-patch+json'

    if ($response.StatusCode -notin @(200,204)) {
        Write-Host "[BLOCKED] Project branding marker write returned HTTP $($response.StatusCode)." -ForegroundColor Red
        throw "Project-Branding-Marker konnte nicht geschrieben werden (HTTP $($response.StatusCode))."
    }
}

function Ensure-BSSEProjectAvatar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [switch]$Apply
    )

    # Asset validation happens even when the project does not exist yet. This makes a
    # missing/corrupt repository asset visible during the provisioning dry run.
    $asset = Get-BSSEProjectAvatarAsset -ProjectName $ProjectName

    $project = Get-BSSEProjectForBranding `
        -OrganizationUrl $OrganizationUrl `
        -ProjectName $ProjectName `
        -Attempts $(if ($Apply) { 10 } else { 1 })

    if (-not $project) {
        if (-not $Apply) {
            Write-Host "  [PLAN] Project avatar $ProjectName <- $($asset.RelativePath) (after project creation)" -ForegroundColor Yellow
            return [pscustomobject]@{
                ProjectName = $ProjectName
                Asset       = $asset.RelativePath
                Sha256      = $asset.Sha256
                State       = 'PlannedAfterProjectCreation'
            }
        }

        Write-Host "[BLOCKED] Project '$ProjectName' could not be resolved for branding after provisioning." -ForegroundColor Red
        throw "Project '$ProjectName' wurde für Project Branding nicht gefunden bzw. besitzt keine ermittelte Project-ID."
    }

    if (-not $project.id) {
        Write-Host "[BLOCKED] Project '$ProjectName' has no resolved project ID for branding." -ForegroundColor Red
        throw "Project-ID für '$ProjectName' konnte nicht ermittelt werden."
    }

    $marker = Get-BSSEProjectAvatarHashMarker `
        -OrganizationUrl $OrganizationUrl `
        -ProjectId ([string]$project.id)

    if ($marker -and $marker.Equals($asset.Sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "  [EXISTS] Project avatar $ProjectName <- $($asset.RelativePath) (managed SHA-256 marker matches)" -ForegroundColor DarkGray
        return [pscustomobject]@{
            ProjectName = $ProjectName
            ProjectId   = [string]$project.id
            Asset       = $asset.RelativePath
            Sha256      = $asset.Sha256
            State       = 'ExistsByManagedMarker'
        }
    }

    if (-not $Apply) {
        $reason = if ([string]::IsNullOrWhiteSpace($marker)) { 'managed marker missing' } else { 'managed marker differs' }
        Write-Host "  [PLAN] Set project avatar $ProjectName <- $($asset.RelativePath) ($reason)" -ForegroundColor Yellow
        return [pscustomobject]@{
            ProjectName = $ProjectName
            ProjectId   = [string]$project.id
            Asset       = $asset.RelativePath
            Sha256      = $asset.Sha256
            State       = 'Planned'
        }
    }

    $imageBytes = [System.IO.File]::ReadAllBytes($asset.FullPath)
    # Microsoft documents ProjectAvatar.image as a byte array. ConvertTo-Json emits the
    # Byte[] as the numeric JSON array expected by the Azure DevOps Core API.
    $payload = @{
        image = @($imageBytes)
    } | ConvertTo-Json -Depth 5 -Compress

    $avatarUrl = "$($OrganizationUrl.TrimEnd('/'))/_apis/projects/$($project.id)/avatar?api-version=7.1-preview.1"

    Write-Host "  [SET] Project avatar $ProjectName <- $($asset.RelativePath)" -ForegroundColor Green
    $avatarResponse = Invoke-BSSEProjectBrandingRest `
        -Method PUT `
        -Url $avatarUrl `
        -Body $payload `
        -ContentType 'application/json'

    # Microsoft currently documents HTTP 200 for Set Project Avatar. The first real
    # BSSE-CloudOps runtime on 2026-08-13 returned HTTP 204 for the successful PUT.
    # Accept both observed/documented success statuses, then rely on the managed marker
    # write + readback below before considering the desired state verified.
    if ($avatarResponse.StatusCode -notin @(200,204)) {
        Write-Host "[BLOCKED] Project Avatar API returned HTTP $($avatarResponse.StatusCode) for '$ProjectName'." -ForegroundColor Red
        throw "Project Avatar API für '$ProjectName' wurde nicht erfolgreich bestätigt."
    }

    # Only record the managed desired-state marker after the avatar API itself succeeded.
    Set-BSSEProjectAvatarHashMarker `
        -OrganizationUrl $OrganizationUrl `
        -ProjectId ([string]$project.id) `
        -Sha256 $asset.Sha256

    $verifiedMarker = Get-BSSEProjectAvatarHashMarker `
        -OrganizationUrl $OrganizationUrl `
        -ProjectId ([string]$project.id)

    if (-not $verifiedMarker -or -not $verifiedMarker.Equals($asset.Sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "[BLOCKED] Project avatar marker verification failed for '$ProjectName'." -ForegroundColor Red
        throw "Project Avatar wurde per API gesetzt, aber der verwaltete SHA-256-Marker konnte nicht belastbar verifiziert werden."
    }

    Write-Host "  [OK] Project avatar $ProjectName applied (Avatar API HTTP $($avatarResponse.StatusCode); managed SHA-256 marker verified)." -ForegroundColor Green

    return [pscustomobject]@{
        ProjectName = $ProjectName
        ProjectId   = [string]$project.id
        Asset       = $asset.RelativePath
        Sha256      = $asset.Sha256
        State       = 'AppliedAndMarkerVerified'
    }
}
