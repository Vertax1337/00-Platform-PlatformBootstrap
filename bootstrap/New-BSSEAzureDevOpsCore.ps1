[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [string]$OrganizationUrl,

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\BSSE.AzureDevOps.Common.ps1"

$session = Initialize-BSSEAzureDevOpsSession -OrganizationUrl $OrganizationUrl
$OrganizationUrl = $session.OrganizationUrl

$core = @(
    @{
        Name = '00-Platform'
        Description = 'BSSE shared DevOps platform, pipeline templates, documentation engine and security validation.'
        Repositories = @('PlatformBootstrap', 'PipelineTemplates', 'DocumentationEngine', 'SecurityValidation', 'SharedModules')
    },
    @{
        Name = '10-Automation'
        Description = 'BSSE read-only collectors, sanitizers and documentation automation.'
        Repositories = @('10-Automation-AzureInfrastructureCollector', '10-Automation-OPNsenseDocumentation')
        LegacyRepositoryAliases = @{
            '10-Automation-AzureInfrastructureCollector' = @('AzureInfrastructureCollector')
            '10-Automation-OPNsenseDocumentation' = @('OPNsenseDocumentation', 'OpenSenseDocumentation')
        }
    },
    @{
        Name = '20-IaC'
        Description = 'BSSE Infrastructure as Code solutions and reusable IaC modules.'
        Repositories = @('Vaultwarden', 'AVD-Accelerator', 'Shared-IaC-Modules')
    },
    @{
        Name = '99-LAB'
        Description = 'BSSE isolated validation and end-to-end lab project.'
        Repositories = @('LabConfiguration', 'LabDocumentation')
    }
)

function Ensure-ProjectRepositories {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [string[]]$DesiredRepositories,

        [hashtable]$LegacyRepositoryAliases = @{}
    )

    $repos = @(Get-BSSEProjectRepositories -OrganizationUrl $OrganizationUrl -Project $ProjectName)
    $repoNames = @($repos | ForEach-Object { $_.name })
    $firstDesired = $DesiredRepositories[0]

    function Get-LegacyRepositoryMatch {
        param([string]$DesiredRepository)

        if (-not $LegacyRepositoryAliases.ContainsKey($DesiredRepository)) {
            return $null
        }

        foreach ($legacyName in @($LegacyRepositoryAliases[$DesiredRepository])) {
            if ($repoNames -contains $legacyName) {
                return $legacyName
            }
        }

        return $null
    }

    function Assert-NoLegacyOnlyRepository {
        param([string]$DesiredRepository)

        if ($repoNames -contains $DesiredRepository) {
            return
        }

        $legacyMatch = Get-LegacyRepositoryMatch -DesiredRepository $DesiredRepository
        if (-not $legacyMatch) {
            return
        }

        Write-Host "  [BLOCKED] Legacy repo '$legacyMatch' found; expected '$DesiredRepository'." -ForegroundColor Red
        Write-Host "            No repository will be created, renamed or modified automatically." -ForegroundColor DarkGray

        if ($Apply) {
            throw "Legacy repository '$legacyMatch' must be reviewed/renamed manually to '$DesiredRepository' before -Apply."
        }
    }

    if ($repoNames -notcontains $firstDesired) {
        Assert-NoLegacyOnlyRepository -DesiredRepository $firstDesired
        $legacyMatch = Get-LegacyRepositoryMatch -DesiredRepository $firstDesired

        if (-not $legacyMatch) {
            $projectNamedRepo = $repos | Where-Object { $_.name -eq $ProjectName } | Select-Object -First 1

            if ($projectNamedRepo) {
                if (-not $Apply) {
                    Write-Host "  [PLAN] Rename initial repo '$ProjectName' -> '$firstDesired'" -ForegroundColor Yellow
                }
                else {
                    Write-Host "  [RENAME] Initial repo '$ProjectName' -> '$firstDesired'" -ForegroundColor Green

                    Invoke-BSSEAzDevOpsOrThrow -Arguments @(
                        'repos','update',
                        '--org', $OrganizationUrl,
                        '--project', $ProjectName,
                        '--repository', $projectNamedRepo.id,
                        '--name', $firstDesired,
                        '--only-show-errors'
                    ) | Out-Null

                    $repoNames = @($repoNames | Where-Object { $_ -ne $ProjectName }) + $firstDesired
                }
            }
            elseif (-not $Apply) {
                Write-Host "  [PLAN] Create repo $firstDesired" -ForegroundColor Yellow
            }
            else {
                Write-Host "  [CREATE] Repo $firstDesired" -ForegroundColor Green
                New-BSSEEmptyGitRepository `
                    -OrganizationUrl $OrganizationUrl `
                    -Project $ProjectName `
                    -RepositoryName $firstDesired

                $repoNames += $firstDesired
            }
        }
    }
    else {
        Write-Host "  [EXISTS] Repo $firstDesired (no change)" -ForegroundColor DarkGray
    }

    foreach ($repo in $DesiredRepositories | Select-Object -Skip 1) {
        if ($repoNames -contains $repo) {
            Write-Host "  [EXISTS] Repo $repo (no change)" -ForegroundColor DarkGray

            $legacyMatch = Get-LegacyRepositoryMatch -DesiredRepository $repo
            if ($legacyMatch) {
                Write-Host "  [WARN] Legacy repo '$legacyMatch' also exists; bootstrap leaves it untouched." -ForegroundColor Yellow
            }
        }
        else {
            Assert-NoLegacyOnlyRepository -DesiredRepository $repo
            $legacyMatch = Get-LegacyRepositoryMatch -DesiredRepository $repo

            if ($legacyMatch) {
                # Dry-run already emitted [BLOCKED]; do not provision a duplicate.
                continue
            }

            if (-not $Apply) {
                Write-Host "  [PLAN] Create repo $repo" -ForegroundColor Yellow
            }
            else {
                Write-Host "  [CREATE] Repo $repo" -ForegroundColor Green
                New-BSSEEmptyGitRepository `
                    -OrganizationUrl $OrganizationUrl `
                    -Project $ProjectName `
                    -RepositoryName $repo

                $repoNames += $repo
            }
        }
    }
}

Write-Host ""
Write-Host "BSSE Azure DevOps Core Bootstrap" -ForegroundColor Cyan
Write-Host "Organization: $OrganizationUrl"
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"
Write-Host ""

$json = Invoke-BSSEAzDevOpsOrThrow -Arguments @(
    'devops','project','list',
    '--org', $OrganizationUrl,
    '--output','json',
    '--only-show-errors'
)
$existingProjects = @((($json | ConvertFrom-Json).value) | ForEach-Object { $_.name })

foreach ($project in $core) {
    $projectExists = $existingProjects -contains $project.Name

    if ($projectExists) {
        Write-Host "[EXISTS] Project $($project.Name)" -ForegroundColor DarkGray
        $legacyAliases = if ($project.ContainsKey('LegacyRepositoryAliases')) { $project.LegacyRepositoryAliases } else { @{} }
        Ensure-ProjectRepositories `
            -ProjectName $project.Name `
            -DesiredRepositories $project.Repositories `
            -LegacyRepositoryAliases $legacyAliases
    }
    elseif (-not $Apply) {
        Write-Host "[PLAN] Create project $($project.Name)" -ForegroundColor Yellow
        Write-Host "  [PLAN] Initial Git repo will become $($project.Repositories[0])" -ForegroundColor Yellow

        foreach ($repo in $project.Repositories | Select-Object -Skip 1) {
            Write-Host "  [PLAN] Create repo $repo" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[CREATE] Project $($project.Name)" -ForegroundColor Green

        Invoke-BSSEAzDevOpsOrThrow -Arguments @(
            'devops','project','create',
            '--org', $OrganizationUrl,
            '--name', $project.Name,
            '--description', $project.Description,
            '--process', 'Basic',
            '--source-control', 'git',
            '--visibility', 'private',
            '--only-show-errors'
        ) | Out-Null

        $legacyAliases = if ($project.ContainsKey('LegacyRepositoryAliases')) { $project.LegacyRepositoryAliases } else { @{} }
        Ensure-ProjectRepositories `
            -ProjectName $project.Name `
            -DesiredRepositories $project.Repositories `
            -LegacyRepositoryAliases $legacyAliases
    }
}

Write-Host ""
if (-not $Apply) {
    Write-Host "Dry Run abgeschlossen. Es wurden keine Azure-DevOps-Objekte verändert." -ForegroundColor Cyan
}
else {
    Write-Host "Core-Projekte und Repositories wurden idempotent angelegt bzw. waren bereits vorhanden." -ForegroundColor Cyan
}