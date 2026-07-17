#Requires -Version 5.1
<#
.SYNOPSIS
    OFFLINE analyzer for the ADLS ACL assessment. Reads data/inventory.json (+ inventory.jsonl) and
    computes the deterministic evidence for the RBAC proposition, writing data/analysis.json.

.DESCRIPTION
    Pure local computation - never contacts Azure or Entra. Produces:
      * summary metrics (sprawl, orphans, effective-access coverage),
      * duplicate group clusters (groups whose folder grants are identical),
      * user personas (users clustered by effective access footprint),
      * a mechanical role-collapse model (per department + access level) and quantified savings,
      * narrative-ready findings.
    The AI layer (GitHub Copilot in GHCP) reads analysis.json to name roles, write rationale, and produce
    the editable recommendations + Excel (M4/M5). Runs on built-in Windows PowerShell 5.1 or PowerShell 7.

.PARAMETER InventoryPath
    Path to inventory.json. Default: <repo>/data/inventory.json
.PARAMETER AceJsonlPath
    Path to inventory.jsonl. Default: <repo>/data/inventory.jsonl
.PARAMETER OutPath
    Path to write analysis.json. Default: <repo>/data/analysis.json

.EXAMPLE
    powershell -File ./analyzer/Invoke-Analysis.ps1
#>
[CmdletBinding()]
param(
    [string]$InventoryPath,
    [string]$AceJsonlPath,
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here
. "$repoRoot/engine/lib/Common.ps1"   # Write-ScanLog helper (no Azure calls)

if (-not $InventoryPath) { $InventoryPath = Join-Path $repoRoot 'data/inventory.json' }
if (-not $AceJsonlPath) { $AceJsonlPath = Join-Path $repoRoot 'data/inventory.jsonl' }
if (-not $OutPath) { $OutPath = Join-Path $repoRoot 'data/analysis.json' }

if (-not (Test-Path $InventoryPath)) {
    throw "Inventory not found: $InventoryPath`nRun the scan first (engine/Invoke-Scan.ps1)."
}

Write-ScanLog OK ("Analyzing {0}" -f $InventoryPath)
$inv = Get-Content -Path $InventoryPath -Raw | ConvertFrom-Json

$groupById = @{}
foreach ($g in $inv.groups) { $groupById[$g.id] = $g }

$folderById = @{}
foreach ($f in $inv.folders) { $folderById[$f.path] = $f }

# --- 1) Group ACE footprints (from the JSONL stream) -------------------------
$groupFootprint = @{}   # groupId -> HashSet[ "folder|perm|scope" ]
$totalAceCount = 0
$namedGroupAceCount = 0
if (Test-Path $AceJsonlPath) {
    foreach ($line in [System.IO.File]::ReadLines($AceJsonlPath)) {
        if (-not $line) { continue }
        $a = $line | ConvertFrom-Json
        $totalAceCount++
        if ($a.isNamed -and $a.principalType -eq 'group' -and $a.principalId) {
            $namedGroupAceCount++
            if (-not $groupFootprint.ContainsKey($a.principalId)) { $groupFootprint[$a.principalId] = New-Object 'System.Collections.Generic.HashSet[string]' }
            [void]$groupFootprint[$a.principalId].Add(('{0}|{1}|{2}' -f $a.folderPath, $a.permissions, $a.scope))
        }
    }
}
else {
    Write-ScanLog WARN ("ACE stream not found ({0}); duplicate/role analysis will be limited." -f $AceJsonlPath)
}

# --- 2) Duplicate group clusters (identical grant footprint) -----------------
$byFootprint = @{}
foreach ($gid in $groupFootprint.Keys) {
    $sig = ((@($groupFootprint[$gid])) | Sort-Object) -join ';'
    if (-not $byFootprint.ContainsKey($sig)) { $byFootprint[$sig] = New-Object 'System.Collections.Generic.List[string]' }
    $byFootprint[$sig].Add($gid)
}
$duplicateClusters = New-Object 'System.Collections.Generic.List[object]'
$dupRemovable = 0
foreach ($sig in $byFootprint.Keys) {
    $ids = $byFootprint[$sig]
    if ($ids.Count -gt 1) {
        $dupRemovable += ($ids.Count - 1)
        $names = foreach ($id in $ids) { if ($groupById.ContainsKey($id)) { $groupById[$id].displayName } else { $id } }
        $duplicateClusters.Add([pscustomobject]@{
                grants        = @($sig -split ';')
                groupCount    = $ids.Count
                keepOne       = $true
                removableCount = $ids.Count - 1
                groupNames    = @($names)
            })
    }
}

# --- 3) Orphan / empty / unused (from hygiene) -------------------------------
$orphan = @($inv.hygiene.orphanGroups)
$emptyGroups = @($orphan | Where-Object { $_.emptyMembers })
$unusedGroups = @($orphan | Where-Object { $_.notOnAnyAce })

# --- 4) Effective membership (transitive) + user access footprints -----------
$userGroups = @{}   # userId -> HashSet[groupId]  (direct)
foreach ($m in $inv.memberships) {
    if ($m.memberType -eq 'user') {
        if (-not $userGroups.ContainsKey($m.memberId)) { $userGroups[$m.memberId] = New-Object 'System.Collections.Generic.HashSet[string]' }
        [void]$userGroups[$m.memberId].Add($m.groupId)
    }
}
$parentsOf = @{}    # childGroupId -> [parentGroupId]  (child is a member of parent)
foreach ($n in $inv.groupNesting) {
    if (-not $parentsOf.ContainsKey($n.childGroupId)) { $parentsOf[$n.childGroupId] = New-Object 'System.Collections.Generic.List[string]' }
    $parentsOf[$n.childGroupId].Add($n.parentGroupId)
}
function Get-EffectiveGroups {
    param($DirectSet)
    $eff = New-Object 'System.Collections.Generic.HashSet[string]'
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($g in $DirectSet) { if ($eff.Add($g)) { $queue.Enqueue($g) } }
    while ($queue.Count -gt 0) {
        $g = $queue.Dequeue()
        if ($parentsOf.ContainsKey($g)) { foreach ($p in $parentsOf[$g]) { if ($eff.Add($p)) { $queue.Enqueue($p) } } }
    }
    return $eff
}
$userAccess = @{}   # userId -> HashSet[ grant string ]
foreach ($uid in $userGroups.Keys) {
    $eff = Get-EffectiveGroups $userGroups[$uid]
    $acc = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($g in $eff) { if ($groupFootprint.ContainsKey($g)) { foreach ($grant in $groupFootprint[$g]) { [void]$acc.Add($grant) } } }
    $userAccess[$uid] = $acc
}

# --- 5) Personas (cluster users by identical effective access) ---------------
$byAccess = @{}
$usersNoAccess = 0
foreach ($u in $inv.users) {
    $acc = $null
    if ($userAccess.ContainsKey($u.id)) { $acc = $userAccess[$u.id] }
    $sig = ''
    if ($acc -and $acc.Count -gt 0) { $sig = ((@($acc)) | Sort-Object) -join ';' } else { $usersNoAccess++ }
    if (-not $byAccess.ContainsKey($sig)) { $byAccess[$sig] = New-Object 'System.Collections.Generic.List[object]' }
    $byAccess[$sig].Add($u)
}
$personas = New-Object 'System.Collections.Generic.List[object]'
$pIdx = 0
foreach ($sig in ($byAccess.Keys | Sort-Object { $byAccess[$_].Count } -Descending)) {
    $members = $byAccess[$sig]
    $pIdx++
    $grants = @()
    if ($sig) { $grants = @($sig -split ';') }
    $titles = @($members | ForEach-Object { $_.jobTitle } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { $_.Name })
    $personas.Add([pscustomobject]@{
            personaId       = ("persona-{0:D3}" -f $pIdx)
            userCount       = $members.Count
            grantCount      = $grants.Count
            commonJobTitles = $titles
            sampleUsers     = @($members | Select-Object -First 5 | ForEach-Object { $_.upn })
            sampleGrants    = @($grants | Select-Object -First 8)
        })
}

# --- 6) Mechanical role-collapse model (per department + access level) -------
function Get-AccessLevel {
    param([string]$perm)
    if ($perm -eq 'rwx') { return 'Owner' }
    if ($perm -match 'w') { return 'Contributor' }
    if ($perm -match 'r') { return 'Reader' }
    return 'Traverse'
}
$roleMap = @{}   # "dept|level" -> HashSet[groupId]
foreach ($gid in $groupFootprint.Keys) {
    foreach ($grant in $groupFootprint[$gid]) {
        $parts = $grant -split '\|'
        $folder = $parts[0]; $perm = $parts[1]
        $level = Get-AccessLevel $perm
        if ($level -eq 'Traverse') { continue }
        $dept = 'root'
        if ($folderById.ContainsKey($folder) -and $folderById[$folder].level1) { $dept = $folderById[$folder].level1 }
        $key = "$dept|$level"
        if (-not $roleMap.ContainsKey($key)) { $roleMap[$key] = New-Object 'System.Collections.Generic.HashSet[string]' }
        [void]$roleMap[$key].Add($gid)
    }
}
$proposedRoles = New-Object 'System.Collections.Generic.List[object]'
foreach ($key in ($roleMap.Keys | Sort-Object)) {
    $parts = $key -split '\|'
    $proposedRoles.Add([pscustomobject]@{
            proposedRole       = ("RBAC_{0}_{1}" -f $parts[0], $parts[1])
            scope              = $parts[0]
            accessLevel        = $parts[1]
            replacesGroupCount = $roleMap[$key].Count
        })
}

# --- 7) Savings --------------------------------------------------------------
$currentGroups = @($inv.groups).Count
$proposedRoleCount = $proposedRoles.Count
$reductionPct = 0
if ($currentGroups -gt 0) { $reductionPct = [Math]::Round((($currentGroups - $proposedRoleCount) / $currentGroups) * 100, 1) }
$savings = [ordered]@{
    currentGroups            = $currentGroups
    proposedRoles            = $proposedRoleCount
    groupsEliminated         = [Math]::Max(0, $currentGroups - $proposedRoleCount)
    reductionPct             = $reductionPct
    orphanGroupsRemovable    = $orphan.Count
    duplicateGroupsRemovable = $dupRemovable
    namedGroupAces           = $namedGroupAceCount
}

# --- 8) Findings (narrative-ready for the AI layer) --------------------------
$findings = New-Object 'System.Collections.Generic.List[object]'
$orphanPct = 0
if ($currentGroups -gt 0) { $orphanPct = [Math]::Round(($orphan.Count / $currentGroups) * 100, 1) }
$findings.Add([pscustomobject]@{ id = 'orphan-sprawl'; severity = 'high'; title = 'Orphaned group sprawl'; detail = ("{0} of {1} groups ({2}%) have no members and/or are not used on any folder - safe to retire." -f $orphan.Count, $currentGroups, $orphanPct) })
if ($dupRemovable -gt 0) { $findings.Add([pscustomobject]@{ id = 'duplicate-grants'; severity = 'medium'; title = 'Duplicate grant groups'; detail = ("{0} group(s) grant exactly the same access as another group (e.g. read-only variants that resolve to r-x) - merge to one." -f $dupRemovable) }) }
$usersTotal = @($inv.users).Count
if ($usersTotal -gt 0) { $findings.Add([pscustomobject]@{ id = 'effective-access'; severity = 'high'; title = 'Low effective access coverage'; detail = ("{0} of {1} users have no effective folder access through the group model - a strong sign the ACL/group graph is over-engineered or misconfigured." -f $usersNoAccess, $usersTotal) }) }
$findings.Add([pscustomobject]@{ id = 'role-collapse'; severity = 'medium'; title = 'Collapsible to a small role model'; detail = ("The {0} folder grants collapse to {1} proposed role(s) (per department + access level) - about a {2}% reduction in groups." -f $namedGroupAceCount, $proposedRoleCount, $reductionPct) })

# --- assemble + write --------------------------------------------------------
$analysis = [ordered]@{
    meta                   = [ordered]@{
        tool         = 'adls-acl-analysis'
        engineVersion = '0.1.0'
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        source       = $inv.meta
    }
    summary                = [ordered]@{
        groups                     = $currentGroups
        orphanGroups               = $orphan.Count
        emptyGroups                = $emptyGroups.Count
        unusedGroups               = $unusedGroups.Count
        duplicateClusters          = $duplicateClusters.Count
        duplicateGroupsRemovable   = $dupRemovable
        folders                    = @($inv.folders).Count
        aces                       = $totalAceCount
        namedGroupAces             = $namedGroupAceCount
        users                      = $usersTotal
        usersWithNoEffectiveAccess = $usersNoAccess
        personas                   = $personas.Count
        proposedRoles              = $proposedRoleCount
    }
    savings                = $savings
    findings               = $findings.ToArray()
    proposedRoles          = $proposedRoles.ToArray()
    personas               = $personas.ToArray()
    duplicateGroupClusters = $duplicateClusters.GetRange(0, [Math]::Min(500, $duplicateClusters.Count)).ToArray()
}

$json = $analysis | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($OutPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-ScanLog OK ("Analysis written: {0}" -f $OutPath)
Write-Host ''
Write-Host ("  groups={0}  orphaned={1} ({2}%)  duplicates-removable={3}" -f $currentGroups, $orphan.Count, $orphanPct, $dupRemovable) -ForegroundColor Cyan
Write-Host ("  users={0}  no-effective-access={1}  personas={2}" -f $usersTotal, $usersNoAccess, $personas.Count) -ForegroundColor Cyan
Write-Host ("  proposed roles={0}  =>  ~{1}% fewer groups" -f $proposedRoleCount, $reductionPct) -ForegroundColor Green
