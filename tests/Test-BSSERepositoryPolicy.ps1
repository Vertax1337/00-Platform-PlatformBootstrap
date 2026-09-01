[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. "$repoRoot\bootstrap\BSSE.AzureDevOps.RepositoryPolicy.ps1"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-ThrowsBlocked {
    param([scriptblock]$Action, [string]$Message)
    $blocked = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -match '\[BLOCKED\]') { $blocked = $true }
        else { throw }
    }
    if (-not $blocked) { throw $Message }
}

function New-NamespaceJson {
    param(
        [int64]$PushBit = 901,
        [int64]$PullRequestBit = 902,
        [switch]$LegacyPushOnly,
        [switch]$MissingPullRequest,
        [switch]$DuplicatePush
    )

    $pushDisplay = if ($LegacyPushOnly) { 'Policy exempt' } else { 'Bypass policies when pushing' }
    $actions = @(
        @{ displayName=$pushDisplay; name='PolicyExempt'; bit=$PushBit },
        @{ displayName='Force push (rewrite history, delete branches and tags)'; name='ForcePush'; bit=2 },
        @{ displayName='Edit policies'; name='EditPolicies'; bit=4 },
        @{ displayName='Manage permissions'; name='ManagePermissions'; bit=8 },
        @{ displayName='Contribute'; name='GenericContribute'; bit=16 }
    )
    if (-not $MissingPullRequest) {
        $actions += @{ displayName='Bypass policies when completing pull requests'; name='PullRequestBypassPolicy'; bit=$PullRequestBit }
    }
    if ($DuplicatePush) {
        $actions += @{ displayName='Bypass policies when pushing'; name='Duplicate'; bit=131072 }
    }

    return (@(@{ namespaceId='git-namespace'; name='Git Repositories'; actions=$actions }) | ConvertTo-Json -Depth 10 -Compress)
}

$script:NamespaceJson = New-NamespaceJson -PushBit 16384 -PullRequestBit 65536
function Invoke-BSSEAz {
    param([string[]]$Arguments)
    return [pscustomobject]@{ ExitCode=0; Output=$script:NamespaceJson }
}

$security = Get-BSSEGitSecurityContract -OrganizationUrl 'https://dev.azure.com/example/'
Assert-True ($security.Actions.PushBypass.Bit -eq 16384) 'Push bypass bit was not resolved dynamically.'
Assert-True ($security.Actions.PullRequestBypass.Bit -eq 65536) 'PR bypass bit was not resolved dynamically.'
Assert-True ($security.Actions.PushBypass.DisplayName -ceq 'Bypass policies when pushing') 'Modern push display name was not preserved.'

$script:NamespaceJson = New-NamespaceJson -LegacyPushOnly
Assert-ThrowsBlocked { Get-BSSEGitSecurityContract -OrganizationUrl 'https://dev.azure.com/example/' } 'Legacy-only PolicyExempt action did not block.'

$script:NamespaceJson = New-NamespaceJson -MissingPullRequest
Assert-ThrowsBlocked { Get-BSSEGitSecurityContract -OrganizationUrl 'https://dev.azure.com/example/' } 'Missing modern PR bypass action did not block.'

$script:NamespaceJson = New-NamespaceJson -DuplicatePush
Assert-ThrowsBlocked { Get-BSSEGitSecurityContract -OrganizationUrl 'https://dev.azure.com/example/' } 'Duplicate modern push action did not block.'

$moduleSource = Get-Content -LiteralPath "$repoRoot\bootstrap\BSSE.AzureDevOps.RepositoryPolicy.ps1" -Raw
Assert-True (-not ($moduleSource -match '(?<!\d)(128|32768)(?!\d)')) 'Repository policy module contains a hard-coded production bypass bit.'

$script:CapturedAclUri = ''
function Invoke-BSSERepositoryPolicyRest {
    param([string]$Uri)
    $script:CapturedAclUri = $Uri
    return [pscustomobject]@{ value=@() }
}
Get-BSSEBranchAcl -OrganizationUrl 'https://dev.azure.com/example/' -NamespaceId 'git-namespace' -BranchToken 'repoV2/project/repo/refs/heads/master' | Out-Null
Assert-True ($script:CapturedAclUri -match '/accesscontrollists/git-namespace\?token=') 'Branch ACL URI did not delimit the namespace variable correctly.'

$script:CapturedAclUri = ''
function Invoke-BSSERepositoryPolicyRest {
    param([string]$Uri)
    $script:CapturedAclUri = $Uri
    return [pscustomobject]@{
        value=@([pscustomobject]@{
            acesDictionary=[pscustomobject]@{
                user=[pscustomobject]@{
                    descriptor='user'
                    allow=17
                    deny=0
                    extendedInfo=[pscustomobject]@{ effectiveAllow=17 }
                }
            }
        })
    }
}
$aclWithoutEffectiveDeny = Get-BSSEBranchAcl -OrganizationUrl 'https://dev.azure.com/example/' -NamespaceId 'git-namespace' -BranchToken 'repoV2/project/repo/refs/heads/master'
Assert-True ($aclWithoutEffectiveDeny.Entries[0].EffectiveDeny -eq 0) 'Missing effectiveDeny was not normalized to zero.'

$configuration = Get-Content -LiteralPath "$repoRoot\config\repository-policies.json" -Raw | ConvertFrom-Json
$contract = @($configuration.repositories)[0]
$repository = [pscustomobject]@{ id='repo-id'; name='Vaultwarden'; defaultBranch='refs/heads/master' }
$pipeline = [pscustomobject]@{ id=44; name='Vaultwarden-CI' }
$desiredPolicies = @(New-BSSEDesiredPolicies -Contract $contract -Repository $repository -Pipeline $pipeline)
Assert-True ($desiredPolicies.Count -eq 2) 'Expected exactly two desired policies.'
Assert-True (-not ($desiredPolicies.TypeId -contains $script:BSSEMinimumReviewersPolicyType)) 'Minimum-reviewer policy must not be part of Desired State.'
foreach ($policy in $desiredPolicies) {
    $serializedPolicy = ConvertTo-Json -InputObject $policy.Payload -Depth 30
    Assert-True ($serializedPolicy -match '"scope"\s*:\s*\[') "Policy '$($policy.Name)' did not serialize scope as an array."
}

$buildPolicy = $desiredPolicies | Where-Object TypeId -eq $script:BSSEBuildPolicyType
Assert-True ($buildPolicy.Payload.settings.buildDefinitionId -eq 44) 'Pipeline ID was not resolved into build policy.'
Assert-True (-not $buildPolicy.Payload.settings.manualQueueOnly) 'Build validation must be automatic.'
Assert-True (-not $buildPolicy.Payload.settings.queueOnSourceUpdateOnly) 'Target updates must invalidate the build.'
Assert-True ($buildPolicy.Payload.settings.validDuration -eq 0) 'Build validity must be immediate.'

$actualBuildFromApi = [pscustomobject]($buildPolicy.Payload | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
$actualBuildFromApi.settings.PSObject.Properties.Remove('filenamePatterns')
$actualBuildFromApi.settings.validDuration = 0.0
Assert-True (Test-BSSEPolicyMatches -Actual $actualBuildFromApi -Desired $buildPolicy.Payload) 'API-normalized empty path filters or numeric validDuration did not match.'
$actualBuildFromApi.settings | Add-Member -NotePropertyName filenamePatterns -NotePropertyValue @('/unexpected/*')
Assert-True (-not (Test-BSSEPolicyMatches -Actual $actualBuildFromApi -Desired $buildPolicy.Payload)) 'Unexpected build path filter drift was not detected.'

$obsoleteManagedPolicies = @(New-BSSEObsoleteManagedPolicies -Contract $contract -Repository $repository)
Assert-True ($obsoleteManagedPolicies.Count -eq 1) 'Expected exactly one explicitly recorded obsolete managed policy signature.'
$oldManagedReviewer = [pscustomobject]($obsoleteManagedPolicies[0].Payload | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
$oldManagedReviewer | Add-Member -NotePropertyName id -NotePropertyValue 77
$obsoleteActions = @(Get-BSSEObsoleteManagedPolicyActions -ExistingPolicies @($oldManagedReviewer) -ObsoleteManagedPolicies $obsoleteManagedPolicies -DesiredPolicyTypeIds @($desiredPolicies.TypeId))
Assert-True ($obsoleteActions.Count -eq 1 -and $obsoleteActions[0].Action -eq 'DeleteManagedDrift' -and $obsoleteActions[0].PolicyId -eq 77) 'Exact old managed reviewer policy was not recognized as removable drift.'

$foreignReviewer = [pscustomobject]($obsoleteManagedPolicies[0].Payload | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
$foreignReviewer | Add-Member -NotePropertyName id -NotePropertyValue 78
$foreignReviewer.settings.minimumApproverCount = 2
Assert-ThrowsBlocked { Get-BSSEObsoleteManagedPolicyActions -ExistingPolicies @($foreignReviewer) -ObsoleteManagedPolicies $obsoleteManagedPolicies -DesiredPolicyTypeIds @($desiredPolicies.TypeId) } 'Foreign reviewer policy was not preserved and blocked.'

$script:RemovedManagedPolicyArguments = $null
function Invoke-BSSEAz {
    param([string[]]$Arguments)
    $script:RemovedManagedPolicyArguments = @($Arguments)
    [pscustomobject]@{ ExitCode=0; Output='' }
}
Remove-BSSEManagedPolicyConfiguration -OrganizationUrl 'https://dev.azure.com/example/' -Project '20-IaC' -PolicyId 77
Assert-True (($script:RemovedManagedPolicyArguments[0..3] -join ' ') -eq 'repos policy delete --org') 'Managed drift removal used an unexpected command.'
Assert-True ($script:RemovedManagedPolicyArguments -contains '--yes') 'Managed drift removal was not non-interactively constrained.'
Assert-True ($script:RemovedManagedPolicyArguments -contains '77') 'Managed drift removal targeted the wrong policy ID.'

$securityForAcl = [pscustomobject]@{
    NamespaceId='git-namespace'
    Actions=[pscustomobject]@{
        PushBypass=[pscustomobject]@{ DisplayName='Bypass policies when pushing'; ActionName='PolicyExempt'; Bit=16384 }
        PullRequestBypass=[pscustomobject]@{ DisplayName='Bypass policies when completing pull requests'; ActionName='PullRequestBypassPolicy'; Bit=65536 }
        ForcePush=[pscustomobject]@{ Bit=2 }
        EditPolicies=[pscustomobject]@{ Bit=4 }
        ManagePermissions=[pscustomobject]@{ Bit=8 }
        Contribute=[pscustomobject]@{ Bit=16 }
    }
}

$cleanAcl = [pscustomobject]@{ Entries=@([pscustomobject]@{ Descriptor='normal'; DirectAllow=0; DirectDeny=0; EffectiveAllow=0; EffectiveDeny=0 }) }
Assert-BSSENoForeignBypassDrift -Acl $cleanAcl -SecurityContract $securityForAcl

$foreignAcl = [pscustomobject]@{ Entries=@([pscustomobject]@{ Descriptor='foreign'; DirectAllow=16384; DirectDeny=0; EffectiveAllow=16384; EffectiveDeny=0 }) }
Assert-ThrowsBlocked { Assert-BSSENoForeignBypassDrift -Acl $foreignAcl -SecurityContract $securityForAcl } 'Foreign push bypass did not block.'
Assert-BSSENoForeignBypassDrift -Acl $foreignAcl -SecurityContract $securityForAcl -ManagedDescriptors @('foreign')

$script:IncidentHasContribute = $true
function Get-BSSEPermissionState {
    param($OrganizationUrl,$NamespaceId,$BranchToken,$Subject)
    $allow = if ($script:IncidentHasContribute) { 16 } else { 0 }
    return [pscustomobject]@{ Subject=$Subject; Descriptor=$Subject; DirectAllow=0; DirectDeny=0; EffectiveAllow=$allow; EffectiveDeny=0 }
}
Test-BSSEBreakGlassIncidentPrerequisite -OrganizationUrl 'https://dev.azure.com/example/' -SecurityContract $securityForAcl -BranchToken 'branch' -Subject 'admin@example.com' | Out-Null
$script:IncidentHasContribute = $false
Assert-ThrowsBlocked { Test-BSSEBreakGlassIncidentPrerequisite -OrganizationUrl 'https://dev.azure.com/example/' -SecurityContract $securityForAcl -BranchToken 'branch' -Subject 'admin@example.com' } 'Missing incident Contribute did not block.'

# End-to-end Dry Run with mocked Azure DevOps dependencies. No mutating helper may run.
$script:MutationCalled = $false
function Get-BSSEPolicyProject { [pscustomobject]@{ id='project-id'; name='20-IaC' } }
function Get-BSSEPolicyRepository { [pscustomobject]@{ id='repo-id'; name='Vaultwarden'; defaultBranch='refs/heads/master' } }
function Get-BSSEPolicyPipeline { [pscustomobject]@{ id=44; revision=2; name='Vaultwarden-CI'; process=[pscustomobject]@{ yamlFilename='pipelines/validate.yml' } } }
function Get-BSSEGitSecurityContract { $securityForAcl }
function Get-BSSEProjectGroups {
    @(
        [pscustomobject]@{ displayName='20-IaC Team'; principalName='[20-IaC]\20-IaC Team'; descriptor='team' },
        [pscustomobject]@{ displayName='Contributors'; principalName='[20-IaC]\Contributors'; descriptor='contributors' }
    )
}
function Get-BSSEBranchAcl { [pscustomobject]@{ Token='branch'; Entries=@() } }
function Get-BSSERecursiveGroupUsers { @([pscustomobject]@{ displayName='Normal User'; principalName='normal@example.com'; descriptor='user' }) }
function Get-BSSEPermissionState { [pscustomobject]@{ Subject='normal@example.com'; Descriptor='normal'; DirectAllow=0; DirectDeny=0; EffectiveAllow=0; EffectiveDeny=0 } }
function Get-BSSEPoliciesForBranch { @($oldManagedReviewer) }
function Invoke-BSSEPolicyConfigurationMutation { $script:MutationCalled = $true; throw 'Mutation called during Dry Run.' }
function Remove-BSSEManagedPolicyConfiguration { $script:MutationCalled = $true; throw 'Deletion called during Dry Run.' }

$dryRun = Invoke-BSSERepositoryPolicyReconciliation -OrganizationUrl 'https://dev.azure.com/example/' -Contract $contract
Assert-True ($dryRun.status -eq 'plan') 'Dry Run did not return plan status.'
Assert-True (-not $script:MutationCalled) 'Dry Run invoked a mutating policy helper.'

# A normal user receiving bypass transitively is blocked by effective permission evaluation.
function Get-BSSEPermissionState {
    [pscustomobject]@{ Subject='normal@example.com'; Descriptor='normal'; DirectAllow=0; DirectDeny=0; EffectiveAllow=16384; EffectiveDeny=0 }
}
Assert-ThrowsBlocked { Invoke-BSSERepositoryPolicyReconciliation -OrganizationUrl 'https://dev.azure.com/example/' -Contract $contract } 'Transitive/effective normal-user bypass did not block.'

function Get-BSSEPermissionState {
    [pscustomobject]@{ Subject='normal@example.com'; Descriptor='normal'; DirectAllow=65536; DirectDeny=0; EffectiveAllow=65536; EffectiveDeny=0 }
}
Assert-ThrowsBlocked { Invoke-BSSERepositoryPolicyReconciliation -OrganizationUrl 'https://dev.azure.com/example/' -Contract $contract } 'Direct normal-user PR bypass did not block.'

# Existing Break Glass group with any explicit non-bypass right is blocked.
function Get-BSSEProjectGroups {
    @(
        [pscustomobject]@{ displayName='20-IaC Team'; principalName='[20-IaC]\20-IaC Team'; descriptor='team' },
        [pscustomobject]@{ displayName='Contributors'; principalName='[20-IaC]\Contributors'; descriptor='contributors' },
        [pscustomobject]@{ displayName='Vaultwarden Protected Branch Break Glass'; principalName='[20-IaC]\Vaultwarden Protected Branch Break Glass'; descriptor='breakglass' }
    )
}
function Get-BSSEGroupMembers { @() }
function Get-BSSERecursiveGroupUsers { @() }
function Get-BSSEPermissionState {
    [pscustomobject]@{ Subject='breakglass'; Descriptor='breakglass-legacy'; DirectAllow=2; DirectDeny=0; EffectiveAllow=2; EffectiveDeny=0 }
}
Assert-ThrowsBlocked { Invoke-BSSERepositoryPolicyReconciliation -OrganizationUrl 'https://dev.azure.com/example/' -Contract $contract } 'Force push on Break Glass group did not block.'

foreach ($forbiddenBit in @(4,8,16)) {
    $script:ForbiddenBit = $forbiddenBit
    function Get-BSSEPermissionState {
        [pscustomobject]@{ Subject='breakglass'; Descriptor='breakglass-legacy'; DirectAllow=$script:ForbiddenBit; DirectDeny=0; EffectiveAllow=$script:ForbiddenBit; EffectiveDeny=0 }
    }
    Assert-ThrowsBlocked { Invoke-BSSERepositoryPolicyReconciliation -OrganizationUrl 'https://dev.azure.com/example/' -Contract $contract } "Unexpected Break Glass bit $forbiddenBit did not block."
}

# The exact two dynamically resolved allows are accepted without granting Contribute or other rights.
function Get-BSSEPermissionState {
    $bits = [int64]16384 -bor [int64]65536
    [pscustomobject]@{ Subject='breakglass'; Descriptor='breakglass'; DirectAllow=$bits; DirectDeny=0; EffectiveAllow=$bits; EffectiveDeny=0 }
}
function Get-BSSEBranchAcl { [pscustomobject]@{ Token='branch'; Entries=@([pscustomobject]@{ Descriptor='breakglass'; DirectAllow=([int64]16384 -bor [int64]65536); DirectDeny=0; EffectiveAllow=([int64]16384 -bor [int64]65536); EffectiveDeny=0 }) } }
function Get-BSSEPoliciesForBranch {
    $index = 100
    @($desiredPolicies | ForEach-Object {
        $actual = [pscustomobject]($_.Payload | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
        $actual | Add-Member -NotePropertyName id -NotePropertyValue $index
        $index++
        $actual
    })
}
$exactBreakGlass = Invoke-BSSERepositoryPolicyReconciliation -OrganizationUrl 'https://dev.azure.com/example/' -Contract $contract
Assert-True ($exactBreakGlass.breakGlass.action -eq 'Exists') 'Exact modern Break Glass ACE was not accepted as EXISTS.'
Assert-True ($exactBreakGlass.status -eq 'verified') 'Repeated reconciliation with two exact policies was not idempotently verified.'

# Rollback verifies the recorded semantics, resets only both modern bits, and preserves foreign ACEs.
$recordedApply = [pscustomobject]@{
    status='applied-and-verified'
    repository=[pscustomobject]@{ id='repo-id'; branch='refs/heads/master' }
    securityNamespace=[pscustomobject]@{
        id='git-namespace'
        pushBypass=[pscustomobject]@{ DisplayName='Bypass policies when pushing'; ActionName='PolicyExempt'; Bit=16384 }
        pullRequestBypass=[pscustomobject]@{ DisplayName='Bypass policies when completing pull requests'; ActionName='PullRequestBypassPolicy'; Bit=65536 }
    }
    breakGlass=[pscustomobject]@{ descriptor='breakglass' }
}
$script:RollbackPermissionRead = 0
$script:RollbackResetCalled = 0
function Get-BSSEPermissionState {
    $script:RollbackPermissionRead++
    $allow = if ($script:RollbackPermissionRead -eq 1) { [int64]16384 -bor [int64]65536 } else { 0 }
    [pscustomobject]@{ Subject='breakglass'; Descriptor='breakglass'; DirectAllow=$allow; DirectDeny=0; EffectiveAllow=$allow; EffectiveDeny=0 }
}
function Get-BSSEBranchAcl {
    [pscustomobject]@{ Token='branch'; Entries=@(
        [pscustomobject]@{ Descriptor='breakglass'; DirectAllow=0; DirectDeny=0; EffectiveAllow=0; EffectiveDeny=0 },
        [pscustomobject]@{ Descriptor='foreign'; DirectAllow=77; DirectDeny=11; EffectiveAllow=77; EffectiveDeny=11 }
    ) }
}
function Invoke-BSSEAz {
    param([string[]]$Arguments)
    $script:RollbackResetCalled++
    Assert-True ($Arguments[0..3] -join ' ' -eq 'devops security permission reset') 'Rollback used an unexpected Azure CLI operation.'
    $permissionIndex = [array]::IndexOf($Arguments, '--permission-bit')
    Assert-True ($permissionIndex -ge 0) 'Rollback did not specify permission-bit.'
    Assert-True ([int64]$Arguments[$permissionIndex + 1] -eq ([int64]16384 -bor [int64]65536)) 'Rollback did not reset exactly both dynamic bypass bits.'
    [pscustomobject]@{ ExitCode=0; Output='{}' }
}
$rollback = Invoke-BSSEBreakGlassPermissionRollback -OrganizationUrl 'https://dev.azure.com/example/' -Contract $contract -RecordedApplySummary $recordedApply
Assert-True ($rollback.status -eq 'rollback-verified') 'Rollback did not return verified status.'
Assert-True ($script:RollbackResetCalled -eq 1) 'Rollback did not perform exactly one targeted reset.'
Assert-True ($rollback.breakGlass.directAllowAfter -eq 0) 'Rollback did not remove both managed allows.'

$recordedApply.securityNamespace.pushBypass.Bit = 999
$script:RollbackResetCalled = 0
Assert-ThrowsBlocked { Invoke-BSSEBreakGlassPermissionRollback -OrganizationUrl 'https://dev.azure.com/example/' -Contract $contract -RecordedApplySummary $recordedApply } 'Changed permission semantics did not block rollback.'
Assert-True ($script:RollbackResetCalled -eq 0) 'Blocked rollback performed a mutation.'

Write-Host '[OK] Repository policy tests cover the exact two-policy contract, controlled obsolete-reviewer removal, modern action resolution, drift, Dry Run isolation and rollback.' -ForegroundColor Green
