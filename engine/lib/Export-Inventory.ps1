#Requires -Version 7.0
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

    $groupsOut = foreach ($g in $GraphResult.Groups) {
        [pscustomobject]@{
            id              = $g.Id
            displayName     = $g.DisplayName
            description     = $g.Description
            kind            = (Get-GroupKind $g.DisplayName $Config)
            securityEnabled = [bool]$g.SecurityEnabled
            mail            = $g.Mail
        }
    }

    # Reference maps for hygiene flags.
    $referenced = @{}
    foreach ($k in $AclResult.PrincipalRefs.Keys) { $referenced[$k] = $true }
    $hasMembers = @{}
    foreach ($m in $GraphResult.Memberships) { $hasMembers[$m.groupId] = $true }
    foreach ($n in $GraphResult.Nesting) { $hasMembers[$n.parentGroupId] = $true }

    $orphanGroups = foreach ($g in $GraphResult.Groups) {
        $empty = -not $hasMembers.ContainsKey($g.Id)
        $unused = -not $referenced.ContainsKey($g.Id)
        if ($empty -or $unused) {
            [pscustomobject]@{ id = $g.Id; displayName = $g.DisplayName; emptyMembers = $empty; notOnAnyAce = $unused }
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
            auth          = [ordered]@{ mode = $Config.auth.mode; account = $account }
            counts        = [ordered]@{
                folders         = $AclResult.Folders.Count
                aces            = $AclResult.AceCount
                groups          = $GraphResult.Groups.Count
                users           = $GraphResult.Users.Count
                memberships     = $GraphResult.Memberships.Count
                groupNesting    = $GraphResult.Nesting.Count
                rbacAssignments = $GraphResult.Rbac.Count
                orphanGroups    = @($orphanGroups).Count
                staleUsers      = @($staleUsers).Count
            }
            notes         = @(
                'READ-ONLY snapshot. Effective (transitive) access is computed later by the offline analyzer.',
                'Container root "/" ACL is not captured in Phase-1 M1 (cmdlets cannot address it); all non-root folder ACLs are captured.'
            )
        }
        folders         = $AclResult.Folders
        groups          = @($groupsOut)
        users           = $GraphResult.Users
        memberships     = $GraphResult.Memberships
        groupNesting    = $GraphResult.Nesting
        rbacAssignments = $GraphResult.Rbac
        hygiene         = [ordered]@{ orphanGroups = @($orphanGroups); staleUsers = @($staleUsers) }
        aceJsonl        = (Split-Path -Leaf $AclResult.AceJsonlPath)
    }

    $dir = Split-Path -Parent $OutPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $inventory | ConvertTo-Json -Depth 12 | Set-Content -Path $OutPath -Encoding utf8

    Write-ScanLog OK ("Inventory written: {0}" -f $OutPath)
    return $inventory.meta.counts
}
