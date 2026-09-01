[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

$script:Scenario = ''
$script:Calls = @()

function New-AzResult {
    param(
        [int]$ExitCode,
        [string]$Output
    )

    return [pscustomobject]@{
        ExitCode = $ExitCode
        Output   = $Output
    }
}

function Invoke-BSSEAz {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $script:Calls += ,@($Arguments)
    $command = $Arguments -join ' '

    switch ($script:Scenario) {
        'DirectHit' {
            if ($command -match 'devops project show') {
                return New-AzResult 0 '{"id":"p1","name":"CUST-11941-Cannon-Deutschland-GmbH","state":"wellFormed"}'
            }
            if ($command -match 'devops project list') {
                return New-AzResult 0 '{"count":0,"value":[]}'
            }
        }

        'Paging' {
            if ($command -match 'devops project list') {
                $skipIndex = [array]::IndexOf($Arguments, '--skip')
                $skip = [int]$Arguments[$skipIndex + 1]
                if ($skip -eq 0) {
                    return New-AzResult 0 '{"count":2,"value":[{"name":"A"},{"name":"B"}]}'
                }
                if ($skip -eq 2) {
                    return New-AzResult 0 '{"count":1,"value":[{"name":"C"}]}'
                }
            }
        }

        'RenamedCustomer' {
            if ($command -match 'devops project show') {
                return New-AzResult 1 'Project not found.'
            }
            if ($command -match 'devops project list') {
                return New-AzResult 0 '{"count":1,"value":[{"name":"CUST-11941-Cannon-Deutschland-Alt-GmbH"}]}'
            }
        }

        'DuplicateCustomerNumber' {
            if ($command -match 'devops project show') {
                return New-AzResult 1 'Project not found.'
            }
            if ($command -match 'devops project list') {
                return New-AzResult 0 '{"count":2,"value":[{"name":"CUST-11941-Cannon-A"},{"name":"CUST-11941-Cannon-B"}]}'
            }
        }
    }

    throw "Unexpected mocked az call in scenario '$($script:Scenario)': $command"
}

. "$repoRoot\bootstrap\BSSE.AzureDevOps.CustomerProject.ps1"

$script:Scenario = 'DirectHit'
$script:Calls = @()
$direct = Resolve-BSSECustomerProject `
    -OrganizationUrl 'https://dev.azure.com/BSSE-CloudOps/' `
    -CustomerNumber '11941' `
    -RequestedProjectName 'CUST-11941-Cannon-Deutschland-GmbH'

if (-not $direct.Exists -or $direct.ProjectName -ne 'CUST-11941-Cannon-Deutschland-GmbH' -or $direct.Source -ne 'DirectLookup') {
    throw "Direct-hit recovery failed: $($direct | ConvertTo-Json -Compress)"
}

$script:Scenario = 'Paging'
$script:Calls = @()
$paged = @(Get-BSSEAzureDevOpsProjects `
    -OrganizationUrl 'https://dev.azure.com/BSSE-CloudOps/' `
    -PageSize 2)

if ($paged.Count -ne 3 -or ($paged.name -join ',') -ne 'A,B,C') {
    throw "Paged project enumeration failed: $($paged | ConvertTo-Json -Compress)"
}

$listCalls = @($script:Calls | Where-Object { ($_ -join ' ') -match 'devops project list' })
if ($listCalls.Count -ne 2) {
    throw "Expected two paged project-list calls, got $($listCalls.Count)."
}

$script:Scenario = 'RenamedCustomer'
$script:Calls = @()
$renamed = Resolve-BSSECustomerProject `
    -OrganizationUrl 'https://dev.azure.com/BSSE-CloudOps/' `
    -CustomerNumber '11941' `
    -RequestedProjectName 'CUST-11941-Cannon-Deutschland-GmbH'

if (-not $renamed.Exists -or $renamed.ProjectName -ne 'CUST-11941-Cannon-Deutschland-Alt-GmbH' -or $renamed.Source -ne 'CustomerNumberSearch') {
    throw "CustomerNumber rename resolution failed: $($renamed | ConvertTo-Json -Compress)"
}

$script:Scenario = 'DuplicateCustomerNumber'
$script:Calls = @()
$duplicateBlocked = $false
try {
    Resolve-BSSECustomerProject `
        -OrganizationUrl 'https://dev.azure.com/BSSE-CloudOps/' `
        -CustomerNumber '11941' `
        -RequestedProjectName 'CUST-11941-Cannon-Deutschland-GmbH' | Out-Null
}
catch {
    if ($_.Exception.Message -match 'Mehrere Azure-DevOps-Projekte verwenden dieselbe CustomerNumber') {
        $duplicateBlocked = $true
    }
    else {
        throw
    }
}

if (-not $duplicateBlocked) {
    throw 'Duplicate CustomerNumber was not blocked.'
}

Write-Host '[OK] Customer-project resolver covers direct recovery, paging, rename fallback and duplicate protection.' -ForegroundColor Green
