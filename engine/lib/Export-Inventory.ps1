#Requires -Version 5.1
<#
  Export-Inventory.ps1 — assembles the normalized, offline-friendly inventory.json from the ADLS +
  Graph scan results. Pure local file assembly; no Azure/Entra access.
#>

function Export-Inventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$AclResult,
        [Parameter(Mandatory)]$GraphResult,
        [Parameter(Mandatory)][string]$OutPath,
        $Connection
    )

    Write-ScanLog OK 'Assembling inventory'

    # Reference / membership maps for behavioural classification.
    $referenced = @{}
    foreach ($k in $AclResult.PrincipalRefs.Keys) { $referenced[$k] = $true }
    $memberCount = @{}
    foreach ($m in $GraphResult.Memberships) {
        if ($memberCount.ContainsKey($m.groupId)) { $memberCount[$m.groupId] = $memberCount[$m.groupId] + 1 } else { $memberCount[$m.groupId] = 1 }
    }
    $isParent = @{}
    foreach ($n in $GraphResult.Nesting) { $isParent[$n.parentGroupId] = $true }
    $reachable = Get-ReachableGroupMap -Memberships $GraphResult.Memberships -Nesting $GraphResult.Nesting

    # Classify each group by its OBSERVED function (naming-independent) and effective-access liveness.
    $groupsOut = New-Object System.Collections.Generic.List[object]
    $orphanGroups = New-Object System.Collections.Generic.List[object]
    $nAccess = 0; $nHybrid = 0; $nRole = 0; $nUnused = 0; $nUnreachable = 0
    foreach ($g in $GraphResult.Groups) {
        $onAce = $referenced.ContainsKey($g.Id)
        $mc = 0; if ($memberCount.ContainsKey($g.Id)) { $mc = $memberCount[$g.Id] }
        $isP = $isParent.ContainsKey($g.Id)
        $hasMem = ($mc -gt 0) -or $isP
        $rch = ($reachable.ContainsKey($g.Id) -and $reachable[$g.Id])
        $role = Get-GroupRole -OnAce $onAce -HasMembers $hasMem
        $status = Get-GroupStatus -Role $role -OnAce $onAce -Reachable $rch
        switch ($role) { 'access' { $nAccess++ } 'hybrid' { $nHybrid++ } 'role' { $nRole++ } 'unused' { $nUnused++ } }
        if ($status -eq 'unreachable') { $nUnreachable++ }
        $groupsOut.Add([pscustomobject]@{
            id              = $g.Id
            displayName     = $g.DisplayName
            description     = $g.Description
            kind            = (Get-GroupKind $g.DisplayName $Config)
            role            = $role
            status          = $status
            onAce           = $onAce
            memberCount     = $mc
            reachable       = $rch
            securityEnabled = [bool]$g.SecurityEnabled
            mail            = $g.Mail
        })
        if ($status -ne 'active') {
            $orphanGroups.Add([pscustomobject]@{ id = $g.Id; displayName = $g.DisplayName; emptyMembers = (-not $hasMem); notOnAnyAce = (-not $onAce); status = $status })
        }
    }
    $staleUsers = foreach ($u in $GraphResult.Users) { if (-not $u.accountEnabled) { $u } }

    $account = if ($Connection) { $Connection.Account } else { $null }

    $inventory = [ordered]@{
        meta            = [ordered]@{
            tool          = 'adls-acl-assessment'
            phase         = 1
            engineVersion = '0.1.0'
            generatedUtc  = (Get-Date).ToUniversalTime().ToString('o')
            target        = [ordered]@{
                tenantId          = $Config.target.tenantId
                subscriptionId    = $Config.target.subscriptionId
                resourceGroupName = $Config.target.resourceGroupName
                storageAccount    = $Config.target.storageAccountName
                fileSystem        = $Config.target.fileSystem
                rootPath          = $Config.target.rootPath
            }
            auth          = [ordered]@{ mode = 'interactive'; account = $account }
            counts        = [ordered]@{
                folders         = $AclResult.Folders.Count
                aces            = $AclResult.AceCount
                groups          = $GraphResult.Groups.Count
                users           = $GraphResult.Users.Count
                memberships     = $GraphResult.Memberships.Count
                groupNesting    = $GraphResult.Nesting.Count
                rbacAssignments = $GraphResult.Rbac.Count
                accessGroups    = $nAccess + $nHybrid
                roleGroups      = $nRole
                unreachableGroups = $nUnreachable
                orphanGroups    = $orphanGroups.Count
                staleUsers      = @($staleUsers).Count
            }
            notes         = @(
                'READ-ONLY snapshot. Groups carry a behavioural role (access/role/hybrid/unused) and an effective-access status (active/unreachable/unused).',
                'Container root "/" ACL IS captured (read via the DFS REST getAccessControl call).'
            )
        }
        folders         = $AclResult.Folders
        groups          = $groupsOut.ToArray()
        users           = $GraphResult.Users
        memberships     = $GraphResult.Memberships
        groupNesting    = $GraphResult.Nesting
        rbacAssignments = $GraphResult.Rbac
        hygiene         = [ordered]@{ orphanGroups = $orphanGroups.ToArray(); staleUsers = @($staleUsers) }
        aceJsonl        = (Split-Path -Leaf $AclResult.AceJsonlPath)
    }

    $dir = Split-Path -Parent $OutPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = $inventory | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($OutPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    Write-ScanLog OK ("Inventory written: {0}" -f $OutPath)
    return $inventory.meta.counts
}
