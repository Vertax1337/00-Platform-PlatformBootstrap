Set-StrictMode -Version Latest

$script:BSSEMinimumReviewersPolicyType = 'fa4e907d-c16b-4a4c-9dfa-4906e5d171dd'
$script:BSSEBuildPolicyType = '0609b952-1397-4640-95ec-e00a01b2c241'
$script:BSSECommentPolicyType = 'c6a1889d-b943-4856-b76f-9e46bb6b0df2'

function ConvertFrom-BSSEPolicyJson {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw "$Context lieferte keine JSON-Ausgabe."
    }

    try {
        return ($Json | ConvertFrom-Json)
    }
    catch {
        throw "$Context lieferte ungültiges JSON: $($_.Exception.Message)"
    }
}

function Invoke-BSSEPolicyAzJson {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Context
    )

    $result = Invoke-BSSEAz -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        throw "$Context fehlgeschlagen.`n$($result.Output)"
    }

    return ConvertFrom-BSSEPolicyJson -Json $result.Output -Context $Context
}

function Get-BSSEGitSecurityContract {
    param([Parameter(Mandatory)][string]$OrganizationUrl)

    $namespaces = @(Invoke-BSSEPolicyAzJson -Context 'Git-Security-Namespace' -Arguments @(
        'devops','security','permission','namespace','list',
        '--org',$OrganizationUrl,
        '--output','json',
        '--only-show-errors'
    ))

    $gitNamespaces = @($namespaces | Where-Object { $_.name -ceq 'Git Repositories' })
    if ($gitNamespaces.Count -ne 1) {
        throw "[BLOCKED] Git-Security-Namespace konnte nicht eindeutig aufgelöst werden (Treffer: $($gitNamespaces.Count))."
    }

    $gitNamespace = $gitNamespaces[0]
    $requiredDisplayNames = [ordered]@{
        PushBypass     = 'Bypass policies when pushing'
        PullRequestBypass = 'Bypass policies when completing pull requests'
        ForcePush      = 'Force push (rewrite history, delete branches and tags)'
        EditPolicies   = 'Edit policies'
        ManagePermissions = 'Manage permissions'
        Contribute     = 'Contribute'
    }

    $resolved = [ordered]@{}
    foreach ($entry in $requiredDisplayNames.GetEnumerator()) {
        $matches = @($gitNamespace.actions | Where-Object { $_.displayName -ceq $entry.Value })
        if ($matches.Count -ne 1) {
            throw "[BLOCKED] Moderne Git-Berechtigung '$($entry.Value)' ist nicht eindeutig verfügbar (Treffer: $($matches.Count)). Kein Legacy-Fallback."
        }

        $action = $matches[0]
        if (-not $action.PSObject.Properties['bit'] -or [int64]$action.bit -le 0) {
            throw "[BLOCKED] Git-Berechtigung '$($entry.Value)' besitzt kein gültiges, zur Laufzeit geliefertes Permission-Bit."
        }

        $resolved[$entry.Key] = [pscustomobject]@{
            DisplayName = [string]$action.displayName
            ActionName  = [string]$action.name
            Bit         = [int64]$action.bit
        }
    }

    return [pscustomobject]@{
        NamespaceId = [string]$gitNamespace.namespaceId
        Actions     = [pscustomobject]$resolved
    }
}

function Get-BSSEPolicyProject {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$Project
    )

    return Invoke-BSSEPolicyAzJson -Context "Projekt '$Project'" -Arguments @(
        'devops','project','show',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--output','json',
        '--only-show-errors'
    )
}

function Get-BSSEPolicyRepository {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Repository
    )

    return Invoke-BSSEPolicyAzJson -Context "Repository '$Project/$Repository'" -Arguments @(
        'repos','show',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--repository',$Repository,
        '--output','json',
        '--only-show-errors'
    )
}

function Get-BSSEPolicyPipeline {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)]$Repository,
        [Parameter(Mandatory)]$BuildValidation
    )

    $pipelines = @(Invoke-BSSEPolicyAzJson -Context "Pipeline-Liste '$($BuildValidation.pipelineName)'" -Arguments @(
        'pipelines','list',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--name',[string]$BuildValidation.pipelineName,
        '--output','json',
        '--only-show-errors'
    ))

    $matches = @($pipelines | Where-Object { $_.name -ceq [string]$BuildValidation.pipelineName })
    if ($matches.Count -ne 1) {
        throw "[BLOCKED] Pipeline '$($BuildValidation.pipelineName)' ist nicht eindeutig (Treffer: $($matches.Count))."
    }

    $pipeline = Invoke-BSSEPolicyAzJson -Context "Pipeline '$($BuildValidation.pipelineName)'" -Arguments @(
        'pipelines','show',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--id',[string]$matches[0].id,
        '--output','json',
        '--only-show-errors'
    )

    $problems = @()
    if ([string]$pipeline.repository.id -ne [string]$Repository.id) { $problems += 'Repository-ID' }
    if ([string]$pipeline.repository.defaultBranch -ne [string]$Repository.defaultBranch) { $problems += 'Default Branch' }
    if ([string]$pipeline.process.yamlFilename -ne [string]$BuildValidation.expectedYamlPath) { $problems += 'YAML-Pfad' }
    if ([string]$pipeline.queueStatus -ne 'enabled') { $problems += 'Queue-Status' }
    if ([string]$pipeline.queue.name -ne 'Azure Pipelines' -or -not [bool]$pipeline.queue.pool.isHosted) { $problems += 'Hosted Queue' }
    if ($problems.Count) {
        throw "[BLOCKED] Pipeline '$($BuildValidation.pipelineName)' verletzt den Vertrag: $($problems -join ', ')."
    }

    return $pipeline
}

function New-BSSEPolicyScope {
    param(
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter(Mandatory)][string]$Branch
    )

    return @([ordered]@{
        repositoryId = $RepositoryId
        refName       = $Branch
        matchKind     = 'Exact'
    })
}

function New-BSSEDesiredPolicies {
    param(
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)]$Repository,
        [Parameter(Mandatory)]$Pipeline
    )

    $scope = @(New-BSSEPolicyScope -RepositoryId ([string]$Repository.id) -Branch ([string]$Contract.branch))

    $build = [ordered]@{
        buildDefinitionId       = [int]$Pipeline.id
        queueOnSourceUpdateOnly = [bool]$Contract.buildValidation.queueOnSourceUpdateOnly
        manualQueueOnly         = [bool]$Contract.buildValidation.manualQueueOnly
        displayName             = [string]$Contract.buildValidation.displayName
        validDuration           = [int]$Contract.buildValidation.validDurationMinutes
        filenamePatterns        = @($Contract.buildValidation.pathFilters)
        scope                   = $scope
    }

    return @(
        [pscustomobject]@{
            Name    = 'Vaultwarden-CI build validation'
            TypeId  = $script:BSSEBuildPolicyType
            Payload = [ordered]@{
                isEnabled  = $true
                isBlocking = $true
                type       = @{ id = $script:BSSEBuildPolicyType }
                settings   = $build
            }
        },
        [pscustomobject]@{
            Name    = 'Comment requirements'
            TypeId  = $script:BSSECommentPolicyType
            Payload = [ordered]@{
                isEnabled  = $true
                isBlocking = $true
                type       = @{ id = $script:BSSECommentPolicyType }
                settings   = [ordered]@{ scope = $scope }
            }
        }
    )
}

function New-BSSEObsoleteManagedPolicies {
    param(
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)]$Repository
    )

    $scope = @(New-BSSEPolicyScope -RepositoryId ([string]$Repository.id) -Branch ([string]$Contract.branch))
    $result = @()
    foreach ($obsolete in @($Contract.obsoleteManagedPolicies)) {
        if ([string]$obsolete.policyType -cne 'MinimumReviewers') {
            throw "[BLOCKED] Unbekannter obsoleteManagedPolicies.policyType '$($obsolete.policyType)'."
        }
        $result += [pscustomobject]@{
            Key = [string]$obsolete.key
            Name = 'Obsolete managed minimum-reviewer policy'
            TypeId = $script:BSSEMinimumReviewersPolicyType
            Payload = [ordered]@{
                isEnabled = $true
                isBlocking = $true
                type = @{ id = $script:BSSEMinimumReviewersPolicyType }
                settings = [ordered]@{
                    minimumApproverCount = [int]$obsolete.minimumApproverCount
                    creatorVoteCounts = [bool]$obsolete.creatorVoteCounts
                    allowDownvotes = [bool]$obsolete.allowDownvotes
                    blockLastPusherVote = [bool]$obsolete.blockLastPusherVote
                    resetOnSourcePush = [bool]$obsolete.resetOnSourcePush
                    resetRejectionsOnSourcePush = [bool]$obsolete.resetRejectionsOnSourcePush
                    requireVoteOnLastIteration = [bool]$obsolete.requireVoteOnLastIteration
                    requireVoteOnEachIteration = [bool]$obsolete.requireVoteOnEachIteration
                    scope = $scope
                }
            }
        }
    }
    return @($result)
}

function ConvertTo-BSSECanonicalJsonValue {
    param($Value)
    return (ConvertTo-Json -InputObject $Value -Depth 30 -Compress)
}

function Get-BSSEOptionalInt64Property {
    param(
        $InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return 0L }
    $property = $InputObject.PSObject.Properties[$Name]
    if (-not $property -or $null -eq $property.Value) { return 0L }
    return [int64]$property.Value
}

function Test-BSSEPolicyMatches {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Desired
    )

    if (-not [bool]$Actual.isEnabled -or -not [bool]$Actual.isBlocking) { return $false }
    if ([string]$Actual.type.id -ne [string]$Desired.type.id) { return $false }

    $actualScopes = @($Actual.settings.scope)
    $desiredScopes = @($Desired.settings.scope)
    if ($actualScopes.Count -ne 1 -or $desiredScopes.Count -ne 1) { return $false }

    foreach ($name in @('repositoryId','refName','matchKind')) {
        if ([string]$actualScopes[0].$name -ine [string]$desiredScopes[0].$name) { return $false }
    }

    foreach ($property in $Desired.settings.GetEnumerator()) {
        if ($property.Key -eq 'scope') { continue }
        $actualProperty = $Actual.settings.PSObject.Properties[$property.Key]
        if ($property.Key -eq 'filenamePatterns') {
            $actualPatterns = @()
            if ($actualProperty) { $actualPatterns = @($actualProperty.Value) }
            $desiredPatterns = @($property.Value)
            if ((ConvertTo-BSSECanonicalJsonValue $actualPatterns) -ne (ConvertTo-BSSECanonicalJsonValue $desiredPatterns)) {
                return $false
            }
            continue
        }
        if (-not $actualProperty) { return $false }
        if ($property.Key -eq 'validDuration') {
            if ([decimal]$actualProperty.Value -ne [decimal]$property.Value) { return $false }
            continue
        }
        if ((ConvertTo-BSSECanonicalJsonValue $actualProperty.Value) -ne (ConvertTo-BSSECanonicalJsonValue $property.Value)) {
            return $false
        }
    }

    return $true
}

function Test-BSSEObsoleteManagedPolicyMatches {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$ObsoleteManagedPolicy
    )

    if (-not (Test-BSSEPolicyMatches -Actual $Actual -Desired $ObsoleteManagedPolicy.Payload)) {
        return $false
    }
    $actualNames = @($Actual.settings.PSObject.Properties.Name | Sort-Object)
    $desiredNames = @($ObsoleteManagedPolicy.Payload.settings.Keys | Sort-Object)
    return (ConvertTo-BSSECanonicalJsonValue $actualNames) -eq (ConvertTo-BSSECanonicalJsonValue $desiredNames)
}

function Get-BSSEObsoleteManagedPolicyActions {
    param(
        [Parameter(Mandatory)]$ExistingPolicies,
        [Parameter(Mandatory)]$ObsoleteManagedPolicies,
        [Parameter(Mandatory)][string[]]$DesiredPolicyTypeIds
    )

    $knownTypeIds = @($DesiredPolicyTypeIds + @($ObsoleteManagedPolicies.TypeId))
    $foreignTypes = @($ExistingPolicies | Where-Object { $knownTypeIds -notcontains [string]$_.type.id })
    if ($foreignTypes.Count) {
        throw "[BLOCKED] Nicht verwaltete zusätzliche Branch-Policies verhindern den exklusiven Zwei-Policy-Vertrag: $(@($foreignTypes.id) -join ', ')."
    }

    $actions = @()
    foreach ($obsolete in @($ObsoleteManagedPolicies)) {
        $matchesByType = @($ExistingPolicies | Where-Object { [string]$_.type.id -eq [string]$obsolete.TypeId })
        if (-not $matchesByType.Count) {
            $actions += [pscustomobject]@{ Key=$obsolete.Key; Name=$obsolete.Name; Action='Absent'; PolicyId=$null }
            continue
        }
        $exact = @($matchesByType | Where-Object { Test-BSSEObsoleteManagedPolicyMatches -Actual $_ -ObsoleteManagedPolicy $obsolete })
        if ($matchesByType.Count -ne 1 -or $exact.Count -ne 1) {
            throw "[BLOCKED] Vorhandene Minimum-Reviewer-Policy ist nicht eindeutig als verwaltete Drift '$($obsolete.Key)' erkennbar und wird nicht gelöscht."
        }
        $actions += [pscustomobject]@{ Key=$obsolete.Key; Name=$obsolete.Name; Action='DeleteManagedDrift'; PolicyId=[int]$exact[0].id }
    }
    return @($actions)
}

function Remove-BSSEManagedPolicyConfiguration {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][int]$PolicyId
    )

    $result = Invoke-BSSEAz -Arguments @(
        'repos','policy','delete',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--id',[string]$PolicyId,
        '--yes',
        '--only-show-errors'
    )
    if ($result.ExitCode -ne 0) {
        throw "Verwaltete obsolete Policy ID $PolicyId konnte nicht gelöscht werden.`n$($result.Output)"
    }
}

function Get-BSSEPoliciesForBranch {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter(Mandatory)][string]$Branch
    )

    $branchName = $Branch -replace '^refs/heads/',''
    return @(Invoke-BSSEPolicyAzJson -Context "Policies '$Project/$branchName'" -Arguments @(
        'repos','policy','list',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--repository-id',$RepositoryId,
        '--branch',$branchName,
        '--output','json',
        '--only-show-errors'
    ))
}

function Invoke-BSSEPolicyConfigurationMutation {
    param(
        [Parameter(Mandatory)][ValidateSet('Create','Update')][string]$Mode,
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)]$Payload,
        [int]$PolicyId
    )

    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $tempFile = [System.IO.Path]::Combine($tempRoot, "bsse-policy-$([guid]::NewGuid().ToString('N')).json")
    $resolvedFile = [System.IO.Path]::GetFullPath($tempFile)
    if (-not $resolvedFile.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Temporäre Policydatei wurde außerhalb des Betriebssystem-Temp-Verzeichnisses aufgelöst.'
    }

    try {
        [System.IO.File]::WriteAllText(
            $resolvedFile,
            (ConvertTo-Json -InputObject $Payload -Depth 40),
            [System.Text.UTF8Encoding]::new($false)
        )

        $arguments = @('repos','policy',$Mode.ToLowerInvariant())
        if ($Mode -eq 'Update') { $arguments += @('--id',[string]$PolicyId) }
        $arguments += @(
            '--org',$OrganizationUrl,
            '--project',$Project,
            '--config',$resolvedFile,
            '--output','json',
            '--only-show-errors'
        )

        return Invoke-BSSEPolicyAzJson -Context "$Mode Policy" -Arguments $arguments
    }
    finally {
        if ([System.IO.File]::Exists($resolvedFile)) {
            [System.IO.File]::Delete($resolvedFile)
        }
    }
}

function Get-BSSEProjectGroups {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$Project
    )

    $response = Invoke-BSSEPolicyAzJson -Context "Gruppen '$Project'" -Arguments @(
        'devops','security','group','list',
        '--org',$OrganizationUrl,
        '--project',$Project,
        '--scope','project',
        '--output','json',
        '--only-show-errors'
    )
    return @($response.graphGroups)
}

function Get-BSSEGroupMembers {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$GroupDescriptor
    )

    $response = Invoke-BSSEPolicyAzJson -Context "Mitglieder '$GroupDescriptor'" -Arguments @(
        'devops','security','group','membership','list',
        '--org',$OrganizationUrl,
        '--id',$GroupDescriptor,
        '--relationship','members',
        '--output','json',
        '--only-show-errors'
    )

    if ($null -eq $response) { return @() }
    return @($response.PSObject.Properties | ForEach-Object { $_.Value })
}

function Get-BSSERecursiveGroupUsers {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string[]]$GroupNames,
        [Parameter(Mandatory)]$ProjectGroups
    )

    $users = @{}
    $visitedGroups = @{}

    function Visit-BSSEGroup {
        param([Parameter(Mandatory)][string]$Descriptor)

        if ($visitedGroups.ContainsKey($Descriptor)) { return }
        $visitedGroups[$Descriptor] = $true

        foreach ($member in @(Get-BSSEGroupMembers -OrganizationUrl $OrganizationUrl -GroupDescriptor $Descriptor)) {
            if ([string]$member.subjectKind -eq 'user') {
                $users[[string]$member.descriptor] = $member
            }
            elseif ([string]$member.subjectKind -eq 'group') {
                Visit-BSSEGroup -Descriptor ([string]$member.descriptor)
            }
        }
    }

    foreach ($groupName in $GroupNames) {
        $matches = @($ProjectGroups | Where-Object { $_.principalName -ceq $groupName })
        if ($matches.Count -ne 1) {
            throw "[BLOCKED] Normale Benutzergruppe '$groupName' ist nicht eindeutig (Treffer: $($matches.Count))."
        }
        Visit-BSSEGroup -Descriptor ([string]$matches[0].descriptor)
    }

    return @($users.Values | Sort-Object displayName)
}

function Get-BSSEPermissionState {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$NamespaceId,
        [Parameter(Mandatory)][string]$BranchToken,
        [Parameter(Mandatory)][string]$Subject
    )

    $records = @(Invoke-BSSEPolicyAzJson -Context "Berechtigungen '$Subject'" -Arguments @(
        'devops','security','permission','list',
        '--org',$OrganizationUrl,
        '--id',$NamespaceId,
        '--subject',$Subject,
        '--token',$BranchToken,
        '--output','json',
        '--only-show-errors'
    ))

    if (-not $records.Count) {
        return [pscustomobject]@{ Subject=$Subject; Descriptor=$null; DirectAllow=0L; DirectDeny=0L; EffectiveAllow=0L; EffectiveDeny=0L }
    }

    $aceProperties = @()
    foreach ($record in $records) {
        if ($record.PSObject.Properties['acesDictionary'] -and $null -ne $record.acesDictionary) {
            $aceProperties += @($record.acesDictionary.PSObject.Properties)
        }
    }
    if ($aceProperties.Count -gt 1) {
        throw "[BLOCKED] Berechtigungsausgabe für '$Subject' enthält mehrere nicht eindeutig zuordenbare ACEs."
    }
    if (-not $aceProperties.Count) {
        return [pscustomobject]@{ Subject=$Subject; Descriptor=$null; DirectAllow=0L; DirectDeny=0L; EffectiveAllow=0L; EffectiveDeny=0L }
    }

    $ace = $aceProperties[0].Value
    $extendedInfo = if ($ace.PSObject.Properties['extendedInfo']) { $ace.extendedInfo } else { $null }
    return [pscustomobject]@{
        Subject        = $Subject
        Descriptor     = [string]$ace.descriptor
        DirectAllow    = Get-BSSEOptionalInt64Property -InputObject $ace -Name 'allow'
        DirectDeny     = Get-BSSEOptionalInt64Property -InputObject $ace -Name 'deny'
        EffectiveAllow = Get-BSSEOptionalInt64Property -InputObject $extendedInfo -Name 'effectiveAllow'
        EffectiveDeny  = Get-BSSEOptionalInt64Property -InputObject $extendedInfo -Name 'effectiveDeny'
    }
}

function Get-BSSERepositoryPolicyAccessToken {
    $token = Invoke-BSSEAz -Arguments @(
        'account','get-access-token',
        '--resource','499b84ac-1321-427f-aa17-267ca6975798',
        '--query','accessToken',
        '--output','tsv',
        '--only-show-errors'
    )
    if ($token.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($token.Output)) {
        throw "Azure-DevOps-Zugriffstoken konnte nicht bezogen werden.`n$($token.Output)"
    }
    return $token.Output.Trim()
}

function Invoke-BSSERepositoryPolicyRest {
    param([Parameter(Mandatory)][string]$Uri)
    $headers = @{ Authorization = "Bearer $(Get-BSSERepositoryPolicyAccessToken)" }
    return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers -ErrorAction Stop
}

function Get-BSSEBranchAcl {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$NamespaceId,
        [Parameter(Mandatory)][string]$BranchToken
    )

    $uri = "$($OrganizationUrl.TrimEnd('/'))/_apis/accesscontrollists/${NamespaceId}?token=$([uri]::EscapeDataString($BranchToken))&includeExtendedInfo=true&recurse=false&api-version=7.1"
    $response = Invoke-BSSERepositoryPolicyRest -Uri $uri
    $items = @($response.value)
    if ($items.Count -gt 1) {
        throw "[BLOCKED] Mehrere ACLs wurden für den exakten Branch-Token geliefert."
    }
    if (-not $items.Count) {
        return [pscustomobject]@{ Token=$BranchToken; Entries=@() }
    }

    $entries = @()
    if ($items[0].acesDictionary) {
        foreach ($property in @($items[0].acesDictionary.PSObject.Properties)) {
            $ace = $property.Value
            $extendedInfo = if ($ace.PSObject.Properties['extendedInfo']) { $ace.extendedInfo } else { $null }
            $entries += [pscustomobject]@{
                Descriptor     = [string]$ace.descriptor
                DirectAllow    = Get-BSSEOptionalInt64Property -InputObject $ace -Name 'allow'
                DirectDeny     = Get-BSSEOptionalInt64Property -InputObject $ace -Name 'deny'
                EffectiveAllow = Get-BSSEOptionalInt64Property -InputObject $extendedInfo -Name 'effectiveAllow'
                EffectiveDeny  = Get-BSSEOptionalInt64Property -InputObject $extendedInfo -Name 'effectiveDeny'
            }
        }
    }

    return [pscustomobject]@{ Token=$BranchToken; Entries=@($entries) }
}

function Assert-BSSENoForeignBypassDrift {
    param(
        [Parameter(Mandatory)]$Acl,
        [Parameter(Mandatory)]$SecurityContract,
        [string[]]$ManagedDescriptors = @()
    )

    $pushBit = [int64]$SecurityContract.Actions.PushBypass.Bit
    $prBit = [int64]$SecurityContract.Actions.PullRequestBypass.Bit
    $findings = @()

    foreach ($entry in @($Acl.Entries)) {
        if ($ManagedDescriptors -contains [string]$entry.Descriptor) { continue }
        $directPush = (([int64]$entry.DirectAllow -band $pushBit) -eq $pushBit)
        $directPr = (([int64]$entry.DirectAllow -band $prBit) -eq $prBit)
        $effectivePush = (([int64]$entry.EffectiveAllow -band $pushBit) -eq $pushBit) -and (([int64]$entry.EffectiveDeny -band $pushBit) -eq 0)
        $effectivePr = (([int64]$entry.EffectiveAllow -band $prBit) -eq $prBit) -and (([int64]$entry.EffectiveDeny -band $prBit) -eq 0)
        if ($directPush -or $directPr -or $effectivePush -or $effectivePr) {
            $findings += [pscustomobject]@{
                Descriptor=$entry.Descriptor
                DirectPushBypass=$directPush
                DirectPullRequestBypass=$directPr
                EffectivePushBypass=$effectivePush
                EffectivePullRequestBypass=$effectivePr
            }
        }
    }

    if ($findings.Count) {
        throw "[BLOCKED] Vorbestehende fremde Bypass-/Legacy-Drift auf dem Zielbranch: $($findings | ConvertTo-Json -Depth 10 -Compress)"
    }
}

function Test-BSSEBreakGlassIncidentPrerequisite {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)]$SecurityContract,
        [Parameter(Mandatory)][string]$BranchToken,
        [Parameter(Mandatory)][string]$Subject
    )

    $state = Get-BSSEPermissionState -OrganizationUrl $OrganizationUrl -NamespaceId $SecurityContract.NamespaceId -BranchToken $BranchToken -Subject $Subject
    $contributeBit = [int64]$SecurityContract.Actions.Contribute.Bit
    $hasContribute = (([int64]$state.EffectiveAllow -band $contributeBit) -eq $contributeBit) -and (([int64]$state.EffectiveDeny -band $contributeBit) -eq 0)
    if (-not $hasContribute) {
        throw "[BLOCKED] Incident-Benutzer '$Subject' besitzt ohne Break-Glass-Mitgliedschaft kein effektives Contribute."
    }
    return $state
}

function Assert-BSSEBypassSecurityContractMatchesRecorded {
    param(
        [Parameter(Mandatory)]$Current,
        [Parameter(Mandatory)]$Recorded
    )

    if ([string]$Current.NamespaceId -ne [string]$Recorded.id) {
        throw '[BLOCKED] Git-Security-Namespace stimmt nicht mit dem protokollierten Apply überein.'
    }

    foreach ($entry in @(
        @{ Name='Bypass policies when pushing'; Current=$Current.Actions.PushBypass; Recorded=$Recorded.pushBypass },
        @{ Name='Bypass policies when completing pull requests'; Current=$Current.Actions.PullRequestBypass; Recorded=$Recorded.pullRequestBypass }
    )) {
        if (-not $entry.Recorded) {
            throw "[BLOCKED] Apply-Nachweis enthält keine protokollierte Action '$($entry.Name)'."
        }
        if (
            [string]$entry.Current.DisplayName -cne [string]$entry.Recorded.DisplayName -or
            [string]$entry.Current.ActionName -cne [string]$entry.Recorded.ActionName -or
            [int64]$entry.Current.Bit -ne [int64]$entry.Recorded.Bit
        ) {
            throw "[BLOCKED] Bedeutung oder Bit der Action '$($entry.Name)' weicht vom protokollierten Apply ab."
        }
    }
}

function Assert-BSSEAclUnchangedExceptDescriptor {
    param(
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)]$After,
        [Parameter(Mandatory)][string]$ManagedDescriptor
    )

    $beforeMap = @{}
    $afterMap = @{}
    foreach ($entry in @($Before.Entries)) {
        if ([string]$entry.Descriptor -ne $ManagedDescriptor) {
            $beforeMap[[string]$entry.Descriptor] = "$([int64]$entry.DirectAllow)|$([int64]$entry.DirectDeny)"
        }
    }
    foreach ($entry in @($After.Entries)) {
        if ([string]$entry.Descriptor -ne $ManagedDescriptor) {
            $afterMap[[string]$entry.Descriptor] = "$([int64]$entry.DirectAllow)|$([int64]$entry.DirectDeny)"
        }
    }

    $changed = ($beforeMap.Count -ne $afterMap.Count)
    if (-not $changed) {
        foreach ($descriptor in @($beforeMap.Keys)) {
            if (-not $afterMap.ContainsKey($descriptor) -or $afterMap[$descriptor] -ne $beforeMap[$descriptor]) {
                $changed = $true
                break
            }
        }
    }
    if ($changed) {
        throw '[BLOCKED] Rollback hat unerwartet eine fremde Branch-ACE verändert.'
    }
}

function Invoke-BSSEBreakGlassPermissionRollback {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)]$RecordedApplySummary
    )

    if ([string]$RecordedApplySummary.status -ne 'applied-and-verified') {
        throw '[BLOCKED] Rollback verlangt einen erfolgreich protokollierten Apply-Nachweis.'
    }

    $project = Get-BSSEPolicyProject -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project)
    $repository = Get-BSSEPolicyRepository -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project) -Repository ([string]$Contract.repository)
    if ([string]$repository.id -ne [string]$RecordedApplySummary.repository.id -or
        [string]$Contract.branch -ne [string]$RecordedApplySummary.repository.branch) {
        throw '[BLOCKED] Apply-Nachweis gehört nicht zum aktuellen Repository-/Branch-Vertrag.'
    }

    $security = Get-BSSEGitSecurityContract -OrganizationUrl $OrganizationUrl
    Assert-BSSEBypassSecurityContractMatchesRecorded -Current $security -Recorded $RecordedApplySummary.securityNamespace

    $branchToken = "repoV2/$($project.id)/$($repository.id)/$($Contract.branch)"
    $groups = @(Get-BSSEProjectGroups -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project))
    $matches = @($groups | Where-Object { $_.displayName -ceq [string]$Contract.breakGlass.groupName })
    if ($matches.Count -ne 1) {
        throw "[BLOCKED] Break-Glass-Gruppe ist für den Rollback nicht eindeutig (Treffer: $($matches.Count))."
    }
    $group = $matches[0]
    if ($RecordedApplySummary.breakGlass.descriptor -and
        [string]$RecordedApplySummary.breakGlass.descriptor -ne [string]$group.descriptor) {
        throw '[BLOCKED] Break-Glass-Descriptor stimmt nicht mit dem protokollierten Apply überein.'
    }

    $members = @(Get-BSSEGroupMembers -OrganizationUrl $OrganizationUrl -GroupDescriptor ([string]$group.descriptor))
    if ($members.Count) {
        throw '[BLOCKED] Break-Glass-Gruppe ist während des Rollbacks nicht leer.'
    }

    $managedBits = [int64]$security.Actions.PushBypass.Bit -bor [int64]$security.Actions.PullRequestBypass.Bit
    $beforePermission = Get-BSSEPermissionState -OrganizationUrl $OrganizationUrl -NamespaceId $security.NamespaceId -BranchToken $branchToken -Subject ([string]$group.descriptor)
    if (([int64]$beforePermission.DirectDeny -band $managedBits) -ne 0) {
        throw '[BLOCKED] Die verwalteten Bypass-Bits liegen unerwartet als Deny vor; Rollback würde ihre Bedeutung nicht eindeutig erhalten.'
    }
    $beforeAcl = Get-BSSEBranchAcl -OrganizationUrl $OrganizationUrl -NamespaceId $security.NamespaceId -BranchToken $branchToken
    $expectedAllow = [int64]$beforePermission.DirectAllow -band (-bnot $managedBits)

    if (([int64]$beforePermission.DirectAllow -band $managedBits) -ne 0) {
        $reset = Invoke-BSSEAz -Arguments @(
            'devops','security','permission','reset',
            '--org',$OrganizationUrl,
            '--id',$security.NamespaceId,
            '--subject',[string]$group.descriptor,
            '--token',$branchToken,
            '--permission-bit',[string]$managedBits,
            '--output','json',
            '--only-show-errors'
        )
        if ($reset.ExitCode -ne 0) {
            throw "Rollback der zwei modernen Break-Glass-Allows ist fehlgeschlagen.`n$($reset.Output)"
        }
    }

    $afterPermission = Get-BSSEPermissionState -OrganizationUrl $OrganizationUrl -NamespaceId $security.NamespaceId -BranchToken $branchToken -Subject ([string]$group.descriptor)
    if ([int64]$afterPermission.DirectAllow -ne $expectedAllow -or
        [int64]$afterPermission.DirectDeny -ne [int64]$beforePermission.DirectDeny) {
        throw '[BLOCKED] Rollback-Read-back entspricht nicht der ausschließlich erwarteten Entfernung der zwei modernen Allows.'
    }

    $afterAcl = Get-BSSEBranchAcl -OrganizationUrl $OrganizationUrl -NamespaceId $security.NamespaceId -BranchToken $branchToken
    Assert-BSSEAclUnchangedExceptDescriptor -Before $beforeAcl -After $afterAcl -ManagedDescriptor ([string]$afterPermission.Descriptor)

    return [pscustomobject]@{
        schemaVersion = 1
        status = 'rollback-verified'
        mode = 'Rollback'
        organizationUrl = $OrganizationUrl
        project = [pscustomobject]@{ name=$project.name; id=$project.id }
        repository = [pscustomobject]@{ name=$repository.name; id=$repository.id; branch=$Contract.branch; branchToken=$branchToken }
        securityNamespace = [pscustomobject]@{
            id=$security.NamespaceId
            pushBypass=$security.Actions.PushBypass
            pullRequestBypass=$security.Actions.PullRequestBypass
        }
        breakGlass = [pscustomobject]@{
            groupName=$Contract.breakGlass.groupName
            descriptor=$group.descriptor
            directAllowBefore=$beforePermission.DirectAllow
            directAllowAfter=$afterPermission.DirectAllow
            directDenyBefore=$beforePermission.DirectDeny
            directDenyAfter=$afterPermission.DirectDeny
            memberCount=0
        }
        preRollbackAcl = $beforeAcl
        postRollbackAcl = $afterAcl
    }
}

function Invoke-BSSERepositoryPolicyReconciliation {
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)]$Contract,
        [switch]$Apply
    )

    $project = Get-BSSEPolicyProject -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project)
    $repository = Get-BSSEPolicyRepository -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project) -Repository ([string]$Contract.repository)
    if ([string]$repository.defaultBranch -ne [string]$Contract.branch) {
        throw "[BLOCKED] Default Branch '$($repository.defaultBranch)' entspricht nicht '$($Contract.branch)'."
    }

    $pipeline = Get-BSSEPolicyPipeline -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project) -Repository $repository -BuildValidation $Contract.buildValidation
    $security = Get-BSSEGitSecurityContract -OrganizationUrl $OrganizationUrl
    $branchToken = "repoV2/$($project.id)/$($repository.id)/$($Contract.branch)"
    $groups = @(Get-BSSEProjectGroups -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project))
    $preApplyGroups = @($groups | Select-Object displayName, principalName, descriptor, originId)
    $breakGlassMatches = @($groups | Where-Object { $_.displayName -ceq [string]$Contract.breakGlass.groupName })
    if ($breakGlassMatches.Count -gt 1) {
        throw "[BLOCKED] Break-Glass-Gruppe '$($Contract.breakGlass.groupName)' ist mehrfach vorhanden."
    }

    $breakGlassGroup = if ($breakGlassMatches.Count -eq 1) { $breakGlassMatches[0] } else { $null }
    $managedDescriptors = @()
    $breakGlassPermission = $null
    if ($breakGlassGroup) {
        $members = @(Get-BSSEGroupMembers -OrganizationUrl $OrganizationUrl -GroupDescriptor ([string]$breakGlassGroup.descriptor))
        if ($members.Count) {
            throw "[BLOCKED] Break-Glass-Gruppe ist im Normalzustand nicht leer: $($members.displayName -join ', ')."
        }
        $breakGlassPermission = Get-BSSEPermissionState -OrganizationUrl $OrganizationUrl -NamespaceId $security.NamespaceId -BranchToken $branchToken -Subject ([string]$breakGlassGroup.descriptor)
        $managedDescriptors += @([string]$breakGlassGroup.descriptor, [string]$breakGlassPermission.Descriptor) | Where-Object { $_ }
    }

    $preAcl = Get-BSSEBranchAcl -OrganizationUrl $OrganizationUrl -NamespaceId $security.NamespaceId -BranchToken $branchToken
    Assert-BSSENoForeignBypassDrift -Acl $preAcl -SecurityContract $security -ManagedDescriptors $managedDescriptors

    $normalUsers = @(Get-BSSERecursiveGroupUsers -OrganizationUrl $OrganizationUrl -GroupNames @($Contract.normalUserGroups) -ProjectGroups $groups)
    $normalUserMatrix = @()
    foreach ($user in $normalUsers) {
        $subject = if ($user.principalName) { [string]$user.principalName } else { [string]$user.descriptor }
        $permission = Get-BSSEPermissionState -OrganizationUrl $OrganizationUrl -NamespaceId $security.NamespaceId -BranchToken $branchToken -Subject $subject
        $hasPushBypass = (($permission.EffectiveAllow -band [int64]$security.Actions.PushBypass.Bit) -eq [int64]$security.Actions.PushBypass.Bit) -and (($permission.EffectiveDeny -band [int64]$security.Actions.PushBypass.Bit) -eq 0)
        $hasPrBypass = (($permission.EffectiveAllow -band [int64]$security.Actions.PullRequestBypass.Bit) -eq [int64]$security.Actions.PullRequestBypass.Bit) -and (($permission.EffectiveDeny -band [int64]$security.Actions.PullRequestBypass.Bit) -eq 0)
        $normalUserMatrix += [pscustomobject]@{
            DisplayName=$user.displayName
            PrincipalName=$subject
            EffectiveAllow=$permission.EffectiveAllow
            EffectiveDeny=$permission.EffectiveDeny
            PushBypass=$hasPushBypass
            PullRequestBypass=$hasPrBypass
        }
        if ($hasPushBypass -or $hasPrBypass) {
            throw "[BLOCKED] Normaler Benutzer '$subject' besitzt effektiv ein Bypass-Recht."
        }
    }

    $desiredPolicies = @(New-BSSEDesiredPolicies -Contract $Contract -Repository $repository -Pipeline $pipeline)
    if ($desiredPolicies.Count -ne 2) {
        throw "[BLOCKED] Vaultwarden-Desired-State muss exakt zwei verwaltete Policies enthalten (actual=$($desiredPolicies.Count))."
    }
    $obsoleteManagedPolicies = @(New-BSSEObsoleteManagedPolicies -Contract $Contract -Repository $repository)
    $existingPolicies = @(Get-BSSEPoliciesForBranch -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project) -RepositoryId ([string]$repository.id) -Branch ([string]$Contract.branch))
    $obsoletePolicyActions = @(Get-BSSEObsoleteManagedPolicyActions `
        -ExistingPolicies $existingPolicies `
        -ObsoleteManagedPolicies $obsoleteManagedPolicies `
        -DesiredPolicyTypeIds @($desiredPolicies.TypeId))
    $policyActions = @()
    foreach ($desiredPolicy in $desiredPolicies) {
        $matches = @($existingPolicies | Where-Object { [string]$_.type.id -eq [string]$desiredPolicy.TypeId })
        if ($matches.Count -gt 1) {
            throw "[BLOCKED] Policytyp '$($desiredPolicy.Name)' ist mehrfach auf dem Zielbranch vorhanden."
        }

        if (-not $matches.Count) {
            $policyActions += [pscustomobject]@{ Name=$desiredPolicy.Name; Action='Create'; PolicyId=$null }
        }
        elseif (Test-BSSEPolicyMatches -Actual $matches[0] -Desired $desiredPolicy.Payload) {
            $policyActions += [pscustomobject]@{ Name=$desiredPolicy.Name; Action='Exists'; PolicyId=[int]$matches[0].id }
        }
        else {
            $policyActions += [pscustomobject]@{ Name=$desiredPolicy.Name; Action='Update'; PolicyId=[int]$matches[0].id }
        }
    }

    $pushBit = [int64]$security.Actions.PushBypass.Bit
    $prBit = [int64]$security.Actions.PullRequestBypass.Bit
    $breakGlassBits = $pushBit -bor $prBit
    $breakGlassAction = 'Exists'
    if (-not $breakGlassGroup) {
        $breakGlassAction = 'CreateGroupAndPermissions'
    }
    else {
        $forbiddenBits = @(
            [int64]$security.Actions.ForcePush.Bit,
            [int64]$security.Actions.EditPolicies.Bit,
            [int64]$security.Actions.ManagePermissions.Bit,
            [int64]$security.Actions.Contribute.Bit
        )
        foreach ($bit in $forbiddenBits) {
            if (($breakGlassPermission.DirectAllow -band $bit) -eq $bit) {
                throw "[BLOCKED] Break-Glass-Gruppe besitzt ein unerwartetes explizites Branch-Recht (Bit $bit)."
            }
        }
        $unexpectedDirectAllows = $breakGlassPermission.DirectAllow -band (-bnot $breakGlassBits)
        if ($unexpectedDirectAllows -ne 0) {
            throw "[BLOCKED] Break-Glass-Gruppe besitzt unerwartete explizite Allow-Bits: $unexpectedDirectAllows."
        }
        if ($breakGlassPermission.DirectDeny -ne 0) {
            throw "[BLOCKED] Break-Glass-Gruppe besitzt unerwartete explizite Deny-Bits: $($breakGlassPermission.DirectDeny)."
        }
        if (($breakGlassPermission.DirectAllow -band $breakGlassBits) -ne $breakGlassBits) {
            $breakGlassAction = 'GrantModernBypassPermissions'
        }
    }

    if (-not $Apply) {
        foreach ($policyAction in $policyActions) {
            Write-Host "[$($policyAction.Action.ToUpperInvariant())] $($policyAction.Name)" -ForegroundColor $(if ($policyAction.Action -eq 'Exists') { 'DarkGray' } else { 'Yellow' })
        }
        foreach ($obsoleteAction in $obsoletePolicyActions) {
            Write-Host "[$($obsoleteAction.Action.ToUpperInvariant())] $($obsoleteAction.Name)" -ForegroundColor $(if ($obsoleteAction.Action -eq 'Absent') { 'DarkGray' } else { 'Yellow' })
        }
        Write-Host "[$($breakGlassAction.ToUpperInvariant())] Break-Glass-Gruppe und moderne Bypass-Berechtigungen" -ForegroundColor $(if ($breakGlassAction -eq 'Exists') { 'DarkGray' } else { 'Yellow' })
    }
    else {
        if (-not $breakGlassGroup) {
            Write-Host "[CREATE] Break-Glass-Gruppe $($Contract.breakGlass.groupName)" -ForegroundColor Green
            Invoke-BSSEPolicyAzJson -Context 'Break-Glass-Gruppe erstellen' -Arguments @(
                'devops','security','group','create',
                '--org',$OrganizationUrl,
                '--project',[string]$Contract.project,
                '--scope','project',
                '--name',[string]$Contract.breakGlass.groupName,
                '--description',[string]$Contract.breakGlass.description,
                '--output','json',
                '--only-show-errors'
            ) | Out-Null
            $groups = @(Get-BSSEProjectGroups -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project))
            $breakGlassMatches = @($groups | Where-Object { $_.displayName -ceq [string]$Contract.breakGlass.groupName })
            if ($breakGlassMatches.Count -ne 1) { throw '[BLOCKED] Break-Glass-Gruppe konnte nach Erstellung nicht eindeutig gelesen werden.' }
            $breakGlassGroup = $breakGlassMatches[0]
        }

        $currentBreakGlassPermission = Get-BSSEPermissionState -OrganizationUrl $OrganizationUrl -NamespaceId $security.NamespaceId -BranchToken $branchToken -Subject ([string]$breakGlassGroup.descriptor)
        if (($currentBreakGlassPermission.DirectAllow -band $breakGlassBits) -ne $breakGlassBits) {
            Write-Host '[GRANT] Zwei moderne Break-Glass-Bypass-Berechtigungen' -ForegroundColor Green
            $grant = Invoke-BSSEAz -Arguments @(
                'devops','security','permission','update',
                '--org',$OrganizationUrl,
                '--id',$security.NamespaceId,
                '--subject',[string]$breakGlassGroup.descriptor,
                '--token',$branchToken,
                '--allow-bit',[string]$breakGlassBits,
                '--merge','true',
                '--output','json',
                '--only-show-errors'
            )
            if ($grant.ExitCode -ne 0) { throw "Break-Glass-Berechtigungen konnten nicht gesetzt werden.`n$($grant.Output)" }
        }

        foreach ($desiredPolicy in $desiredPolicies) {
            $action = $policyActions | Where-Object { $_.Name -eq $desiredPolicy.Name } | Select-Object -First 1
            if ($action.Action -eq 'Create') {
                Write-Host "[CREATE] Policy $($desiredPolicy.Name)" -ForegroundColor Green
                Invoke-BSSEPolicyConfigurationMutation -Mode Create -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project) -Payload $desiredPolicy.Payload | Out-Null
            }
            elseif ($action.Action -eq 'Update') {
                Write-Host "[UPDATE] Policy $($desiredPolicy.Name) (ID $($action.PolicyId))" -ForegroundColor Green
                Invoke-BSSEPolicyConfigurationMutation -Mode Update -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project) -Payload $desiredPolicy.Payload -PolicyId $action.PolicyId | Out-Null
            }
        }
        foreach ($obsoleteAction in $obsoletePolicyActions | Where-Object Action -eq 'DeleteManagedDrift') {
            Write-Host "[DELETE MANAGED DRIFT] $($obsoleteAction.Name) (ID $($obsoleteAction.PolicyId))" -ForegroundColor Green
            Remove-BSSEManagedPolicyConfiguration `
                -OrganizationUrl $OrganizationUrl `
                -Project ([string]$Contract.project) `
                -PolicyId ([int]$obsoleteAction.PolicyId)
        }
    }

    $finalGroups = @(Get-BSSEProjectGroups -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project))
    $finalBreakGlass = @($finalGroups | Where-Object { $_.displayName -ceq [string]$Contract.breakGlass.groupName })
    $finalPermission = $null
    if ($finalBreakGlass.Count -eq 1) {
        $finalMembers = @(Get-BSSEGroupMembers -OrganizationUrl $OrganizationUrl -GroupDescriptor ([string]$finalBreakGlass[0].descriptor))
        if ($finalMembers.Count) { throw '[BLOCKED] Break-Glass-Gruppe ist nach Reconciliation nicht leer.' }
        $finalPermission = Get-BSSEPermissionState -OrganizationUrl $OrganizationUrl -NamespaceId $security.NamespaceId -BranchToken $branchToken -Subject ([string]$finalBreakGlass[0].descriptor)
        if ($Apply -and $finalPermission.DirectAllow -ne $breakGlassBits) {
            throw "[BLOCKED] Break-Glass-Read-back enthält nicht exakt die zwei modernen Allows (actual=$($finalPermission.DirectAllow), expected=$breakGlassBits)."
        }
        if ($finalPermission.DirectDeny -ne 0) { throw '[BLOCKED] Break-Glass-Read-back enthält unerwartete Denies.' }
    }
    elseif ($Apply) {
        throw '[BLOCKED] Break-Glass-Gruppe fehlt nach Apply.'
    }

    $finalPolicies = @(Get-BSSEPoliciesForBranch -OrganizationUrl $OrganizationUrl -Project ([string]$Contract.project) -RepositoryId ([string]$repository.id) -Branch ([string]$Contract.branch))
    $remainingReviewerPolicies = @($finalPolicies | Where-Object { [string]$_.type.id -eq $script:BSSEMinimumReviewersPolicyType })
    if ($Apply -and $remainingReviewerPolicies.Count) {
        throw '[BLOCKED] Minimum-Reviewer-Policy ist nach Apply weiterhin vorhanden.'
    }
    $finalForeignPolicies = @($finalPolicies | Where-Object { @($desiredPolicies.TypeId) -notcontains [string]$_.type.id -and [string]$_.type.id -ne $script:BSSEMinimumReviewersPolicyType })
    if ($finalForeignPolicies.Count) {
        throw '[BLOCKED] Nicht verwaltete zusätzliche Branch-Policies sind im finalen Read-back vorhanden.'
    }
    $finalPolicySummary = @()
    foreach ($desiredPolicy in $desiredPolicies) {
        $matches = @($finalPolicies | Where-Object { [string]$_.type.id -eq [string]$desiredPolicy.TypeId })
        $verified = ($matches.Count -eq 1 -and (Test-BSSEPolicyMatches -Actual $matches[0] -Desired $desiredPolicy.Payload))
        if ($Apply -and -not $verified) { throw "[BLOCKED] Policy '$($desiredPolicy.Name)' konnte nach Apply nicht exakt verifiziert werden." }
        $finalPolicySummary += [pscustomobject]@{
            Name=$desiredPolicy.Name
            TypeId=$desiredPolicy.TypeId
            PolicyId=if ($matches.Count -eq 1) { [int]$matches[0].id } else { $null }
            Verified=$verified
            Action=($policyActions | Where-Object { $_.Name -eq $desiredPolicy.Name } | Select-Object -First 1).Action
        }
    }

    return [pscustomobject]@{
        schemaVersion = 1
        status = if ($Apply) { 'applied-and-verified' } elseif (($policyActions.Action -contains 'Create') -or ($policyActions.Action -contains 'Update') -or ($obsoletePolicyActions.Action -contains 'DeleteManagedDrift') -or $breakGlassAction -ne 'Exists') { 'plan' } else { 'verified' }
        mode = if ($Apply) { 'Apply' } else { 'DryRun' }
        organizationUrl = $OrganizationUrl
        project = [pscustomobject]@{ name=$project.name; id=$project.id }
        repository = [pscustomobject]@{ name=$repository.name; id=$repository.id; branch=$Contract.branch; branchToken=$branchToken }
        pipeline = [pscustomobject]@{ name=$pipeline.name; id=$pipeline.id; revision=$pipeline.revision; yamlPath=$pipeline.process.yamlFilename }
        securityNamespace = [pscustomobject]@{
            id=$security.NamespaceId
            pushBypass=$security.Actions.PushBypass
            pullRequestBypass=$security.Actions.PullRequestBypass
            forcePush=$security.Actions.ForcePush
            editPolicies=$security.Actions.EditPolicies
            managePermissions=$security.Actions.ManagePermissions
            contribute=$security.Actions.Contribute
        }
        breakGlass = [pscustomobject]@{
            groupName=$Contract.breakGlass.groupName
            descriptor=if ($finalBreakGlass.Count -eq 1) { $finalBreakGlass[0].descriptor } else { $null }
            directAllow=if ($finalPermission) { $finalPermission.DirectAllow } else { 0 }
            directDeny=if ($finalPermission) { $finalPermission.DirectDeny } else { 0 }
            memberCount=0
            action=$breakGlassAction
        }
        normalUsers = $normalUserMatrix
        policies = $finalPolicySummary
        obsoleteManagedPolicies = @($obsoletePolicyActions | ForEach-Object {
            [pscustomobject]@{
                Key=$_.Key
                Name=$_.Name
                PolicyId=$_.PolicyId
                Action=$_.Action
                AbsentAfterReadBack=($remainingReviewerPolicies.Count -eq 0)
            }
        })
        preApplyGroups = $preApplyGroups
        preApplyPolicies = $existingPolicies
        preApplyAcl = $preAcl
    }
}
