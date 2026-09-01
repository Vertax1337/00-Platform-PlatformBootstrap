[CmdletBinding()]
param(
    [string]$OrganizationUrl = 'https://dev.azure.com/BSSE-CloudOps/',
    [Parameter(Mandatory)][string]$RepositoryKey,
    [string]$ConfigurationPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config/repository-policies.json'),
    [string]$OutputPath,
    [switch]$Apply,
    [switch]$Rollback,
    [string]$AppliedStatePath
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"
. "$PSScriptRoot\BSSE.AzureDevOps.RepositoryPolicy.ps1"

$summary = $null
try {
    if ($Apply -and $Rollback) {
        throw '-Apply und -Rollback dürfen nicht gemeinsam verwendet werden.'
    }
    if (($Apply -or $Rollback) -and (Test-BSSEPipelineContext)) {
        throw 'Repository-Policies dürfen nicht aus einer Pipeline heraus privilegiert angewendet oder zurückgerollt werden. Dry Run/Verify bleibt zulässig.'
    }
    if ($Rollback -and [string]::IsNullOrWhiteSpace($AppliedStatePath)) {
        throw '-Rollback verlangt -AppliedStatePath mit dem unveränderten Summary eines erfolgreich verifizierten Apply.'
    }

    $gitCommand = Get-Command git -CommandType Application -ErrorAction Stop
    $sourceRoot = Split-Path $PSScriptRoot -Parent
    if (($Apply -or $Rollback) -and $OutputPath) {
        $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
        $sourcePrefix = [System.IO.Path]::GetFullPath($sourceRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if ($resolvedOutput.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Apply/Rollback-Summary muss außerhalb des PlatformBootstrap-Working-Trees geschrieben werden.'
        }
    }
    $headBefore = (& $gitCommand.Source -C $sourceRoot rev-parse HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $headBefore -notmatch '^[0-9a-f]{40}$') {
        throw "PlatformBootstrap-Quellcommit konnte nicht ermittelt werden: $headBefore"
    }
    $statusBefore = @(& $gitCommand.Source -C $sourceRoot status --porcelain=v1 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "PlatformBootstrap-Working-Tree konnte nicht geprüft werden: $($statusBefore -join [Environment]::NewLine)"
    }
    if (($Apply -or $Rollback) -and $statusBefore.Count) {
        throw 'Apply/Rollback verlangt einen sauberen, vollständig committeten PlatformBootstrap-Working-Tree.'
    }

    $resolvedConfig = (Resolve-Path -LiteralPath $ConfigurationPath -ErrorAction Stop).Path
    $configuration = Get-Content -LiteralPath $resolvedConfig -Raw | ConvertFrom-Json
    if ([int]$configuration.schemaVersion -ne 1) {
        throw "Nicht unterstützte repository-policies.json schemaVersion '$($configuration.schemaVersion)'."
    }

    $contracts = @($configuration.repositories | Where-Object { $_.key -ceq $RepositoryKey })
    if ($contracts.Count -ne 1) {
        throw "RepositoryKey '$RepositoryKey' ist nicht eindeutig konfiguriert (Treffer: $($contracts.Count))."
    }

    Assert-BSSEAzureCli
    $session = Initialize-BSSEAzureDevOpsSession -OrganizationUrl $OrganizationUrl
    $OrganizationUrl = $session.OrganizationUrl

    Write-Host ''
    Write-Host 'BSSE Repository Branch Policy Reconciliation' -ForegroundColor Cyan
    Write-Host "RepositoryKey: $RepositoryKey"
    Write-Host "Mode: $(if ($Rollback) { 'ROLLBACK' } elseif ($Apply) { 'APPLY' } else { 'DRY RUN / VERIFY' })"
    Write-Host ''

    if ($Rollback) {
        $resolvedAppliedState = (Resolve-Path -LiteralPath $AppliedStatePath -ErrorAction Stop).Path
        $recordedApplySummary = Get-Content -LiteralPath $resolvedAppliedState -Raw | ConvertFrom-Json
        $summary = Invoke-BSSEBreakGlassPermissionRollback `
            -OrganizationUrl $OrganizationUrl `
            -Contract $contracts[0] `
            -RecordedApplySummary $recordedApplySummary
    }
    else {
        $summary = Invoke-BSSERepositoryPolicyReconciliation `
            -OrganizationUrl $OrganizationUrl `
            -Contract $contracts[0] `
            -Apply:$Apply
    }

    $headAfter = (& $gitCommand.Source -C $sourceRoot rev-parse HEAD 2>&1 | Out-String).Trim()
    $statusAfter = @(& $gitCommand.Source -C $sourceRoot status --porcelain=v1 2>&1)
    if ($LASTEXITCODE -ne 0 -or $headAfter -ne $headBefore -or ($statusAfter -join "`n") -ne ($statusBefore -join "`n")) {
        throw '[BLOCKED] PlatformBootstrap-HEAD oder Working Tree hat sich während der Reconciliation verändert.'
    }
    $summary | Add-Member -NotePropertyName execution -NotePropertyValue ([pscustomobject]@{
        sourceCommit=$headBefore
        sourceRoot=$sourceRoot
        workingTreeBefore=@($statusBefore)
        workingTreeAfter=@($statusAfter)
    }) -Force

    Write-Host ''
    Write-Host "[OK] Repository-Policy-Status: $($summary.status)" -ForegroundColor Green
}
catch {
    $summary = [pscustomobject]@{
        schemaVersion = 1
        status = 'blocked'
        mode = if ($Rollback) { 'Rollback' } elseif ($Apply) { 'Apply' } else { 'DryRun' }
        repositoryKey = $RepositoryKey
        error = $_.Exception.Message
    }
    Write-Host "[BLOCKED] $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($OutputPath) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        [System.IO.File]::WriteAllText(
            [System.IO.Path]::GetFullPath($OutputPath),
            (ConvertTo-Json -InputObject $summary -Depth 50),
            [System.Text.UTF8Encoding]::new($false)
        )
    }
}

if ($summary.status -eq 'blocked') { exit 1 }
