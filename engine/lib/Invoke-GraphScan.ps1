#Requires -Version 7.0
<#
  Invoke-GraphScan.ps1 — READ-ONLY enumeration of Entra groups, members (nesting + user
  memberships), users, and existing Azure RBAC assignments on the storage account.
  Uses only Get-Mg* and Get-AzRoleAssignment. Transitive/effective membership is computed later
  (offline, by the analyzer) from the direct edges captured here.
#>

function Invoke-GraphScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [hashtable]$PrincipalRefs = @{}
    )

    Write-ScanLog OK 'Graph scan starting'
    $maxAttempts = $Config.scan.retry.maxAttempts
    $baseDelay = $Config.scan.retry.baseDelayMs
    $prefixes = @($Config.groups.namePrefixes)

    # --- groups in scope ---
    $groups = [System.Collections.Generic.List[object]]::new()
    $groupById = @{}
    if ($prefixes.Count -gt 0) {
        foreach ($p in $prefixes) {
            Write-ScanLog INFO ("  querying groups: startswith(displayName,'{0}')" -f $p)
            $res = Invoke-WithRetry -Activity ("Get-MgGroup {0}" -f $p) -MaxAttempts $maxAttempts -BaseDelayMs $baseDelay -ScriptBlock {
                Get-MgGroup -All -Filter "startswith(displayName,'$p')" -Property Id, DisplayName, Description, SecurityEnabled, Mail, MailEnabled
            }
            foreach ($g in @($res)) { if (-not $groupById.ContainsKey($g.Id)) { $groupById[$g.Id] = $g; $groups.Add($g) } }
        }
    }
    else {
        foreach ($id in ($PrincipalRefs.Keys | Where-Object { $PrincipalRefs[$_] -eq 'group' })) {
            try {
                $g = Invoke-WithRetry -Activity ("Get-MgGroup {0}" -f $id) -MaxAttempts $maxAttempts -BaseDelayMs $baseDelay -ScriptBlock {
                    Get-MgGroup -GroupId $id -Property Id, DisplayName, Description, SecurityEnabled, Mail, MailEnabled
                }
                if ($g -and -not $groupById.ContainsKey($g.Id)) { $groupById[$g.Id] = $g; $groups.Add($g) }
            }
            catch { Write-ScanLog WARN ("group {0} not found: {1}" -f $id, $_.Exception.Message) }
        }
    }
    Write-ScanLog OK ("  groups in scope: {0}" -f $groups.Count)

    # --- members => nesting (group->group) + memberships (group->user) ---
    $memberships = [System.Collections.Generic.List[object]]::new()
    $nesting = [System.Collections.Generic.List[object]]::new()
    $userIds = [System.Collections.Generic.HashSet[string]]::new()
    $i = 0; $total = $groups.Count
    foreach ($g in $groups) {
        $i++
        try {
            $members = Invoke-WithRetry -Activity ("members {0}" -f $g.DisplayName) -MaxAttempts $maxAttempts -BaseDelayMs $baseDelay -ScriptBlock {
                Get-MgGroupMember -GroupId $g.Id -All -Property Id
            }
            foreach ($m in @($members)) {
                $type = "$($m.AdditionalProperties['@odata.type'])"
                if ($type -match 'group') {
                    $nesting.Add([pscustomobject]@{ parentGroupId = $g.Id; childGroupId = $m.Id })
                }
                elseif ($type -match 'user') {
                    $memberships.Add([pscustomobject]@{ groupId = $g.Id; memberId = $m.Id; memberType = 'user' })
                    [void]$userIds.Add($m.Id)
                }
                else {
                    $memberships.Add([pscustomobject]@{ groupId = $g.Id; memberId = $m.Id; memberType = ($type -replace '#microsoft.graph.', '') })
                }
            }
        }
        catch { Write-ScanLog WARN ("members failed for {0}: {1}" -f $g.DisplayName, $_.Exception.Message) }

        if ($i % 100 -eq 0 -or $i -eq $total) {
            Write-Progress -Activity 'Enumerating group members' -Status ("{0}/{1}" -f $i, $total) -PercentComplete (($i / [math]::Max($total, 1)) * 100)
            Write-ScanLog INFO ("  group members {0}/{1}" -f $i, $total)
        }
    }
    Write-Progress -Activity 'Enumerating group members' -Completed

    # include user-type ACE principals (e.g. the operator guest) even if not a group member
    foreach ($id in ($PrincipalRefs.Keys | Where-Object { $PrincipalRefs[$_] -eq 'user' })) { [void]$userIds.Add($id) }

    # --- user details ---
    $users = [System.Collections.Generic.List[object]]::new()
    $j = 0; $ut = $userIds.Count
    foreach ($uid in $userIds) {
        $j++
        try {
            $u = Invoke-WithRetry -Activity ("user {0}" -f $uid) -MaxAttempts $maxAttempts -BaseDelayMs $baseDelay -ScriptBlock {
                Get-MgUser -UserId $uid -Property Id, UserPrincipalName, DisplayName, JobTitle, AccountEnabled
            }
            if ($u) {
                $users.Add([pscustomobject]@{
                        id             = $u.Id
                        upn            = $u.UserPrincipalName
                        displayName    = $u.DisplayName
                        jobTitle       = $u.JobTitle
                        accountEnabled = [bool]$u.AccountEnabled
                    })
            }
        }
        catch { Write-ScanLog WARN ("user {0} fetch failed: {1}" -f $uid, $_.Exception.Message) }
        if ($j % 50 -eq 0 -or $j -eq $ut) { Write-ScanLog INFO ("  users {0}/{1}" -f $j, $ut) }
    }
    Write-ScanLog OK ("  users resolved: {0}" -f $users.Count)

    # --- existing Azure RBAC on the storage account (expected empty for ACL-only estates) ---
    $rbac = [System.Collections.Generic.List[object]]::new()
    $rg = $Config.target.resourceGroupName
    if ($rg -and (($null -eq $Config.scan.includeRbacAssignments) -or [bool]$Config.scan.includeRbacAssignments)) {
        $scope = "/subscriptions/$($Config.target.subscriptionId)/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$($Config.target.storageAccountName)"
        try {
            $ras = Invoke-WithRetry -Activity 'Get-AzRoleAssignment' -MaxAttempts $maxAttempts -BaseDelayMs $baseDelay -ScriptBlock {
                Get-AzRoleAssignment -Scope $scope
            }
            foreach ($ra in @($ras)) {
                $rbac.Add([pscustomobject]@{
                        principalId        = $ra.ObjectId
                        principalType      = "$($ra.ObjectType)"
                        roleDefinitionName = $ra.RoleDefinitionName
                        scope              = $ra.Scope
                    })
            }
            Write-ScanLog OK ("  RBAC assignments at account scope: {0}" -f $rbac.Count)
        }
        catch { Write-ScanLog WARN ("RBAC read failed: {0}" -f $_.Exception.Message) }
    }
    else {
        Write-ScanLog INFO '  RBAC capture skipped (set target.resourceGroupName to enable).'
    }

    return [pscustomobject]@{
        Groups      = $groups
        Users       = $users
        Memberships = $memberships
        Nesting     = $nesting
        Rbac        = $rbac
    }
}
