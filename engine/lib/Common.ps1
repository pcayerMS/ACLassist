#Requires -Version 5.1
<#
  Common.ps1 — shared, READ-ONLY helpers for the scan engine. Dot-sourced by Invoke-Scan.ps1.
  No Azure/Entra mutation occurs here; helpers only read config, format output, and parse data.
#>

function Write-ScanLog {
    [CmdletBinding()]
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')][string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message
    )
    $color = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'Gray' } }
    Write-Host ("[{0}] {1,-5} {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message) -ForegroundColor $color
}

function Write-DataPlaneAccessHint {
    <# Prints actionable guidance when an ADLS data-plane call is denied (HTTP 403). #>
    param($Config)
    $acct = $Config.target.storageAccountName
    Write-ScanLog ERROR 'ADLS data-plane request was denied (HTTP 403).'
    Write-Host @"
  Check, in order:

  1) IDENTITY / RBAC - the signed-in identity needs a data-plane role:
       * 'Storage Blob Data Reader' to list, and 'Storage Blob Data Owner' to read ACLs (getAccessControl).
       Verify: Get-AzRoleAssignment -Scope <storage-account-resource-id>
     (A pure RBAC failure returns error code 'AuthorizationPermissionMismatch'.)

  2) NETWORK - if the account is private-endpoint-only (public access Disabled), run where the storage
     FQDN resolves to the private endpoint. Error code 'AuthorizationFailure' points here.
       [System.Net.Dns]::GetHostAddresses('$acct.dfs.core.windows.net')    # expect the PE private IP
       [System.Net.Dns]::GetHostAddresses('$acct.blob.core.windows.net')   # ADLS Gen2 may also need a BLOB PE
     ADLS Gen2 commonly needs BOTH 'dfs' and 'blob' private endpoints + matching private DNS zones.

  3) SAS - if auth.mode='sas', ensure the token has read + list and has not expired.
"@ -ForegroundColor Yellow
}

function Get-ScanConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        $sample = Join-Path (Split-Path -Parent $Path) 'config.sample.json'
        if (Test-Path $sample) {
            Copy-Item -Path $sample -Destination $Path
            Write-Host ''
            Write-Host 'No config/config.json found - created one from config.sample.json.' -ForegroundColor Yellow
            Write-Host ('  {0}' -f $Path) -ForegroundColor Yellow
            Write-Host '  Review the target (tenant / subscription / storage account) before scanning a real environment.' -ForegroundColor Yellow
        }
        else {
            throw "Config not found: $Path`nCopy config/config.sample.json to config/config.json and edit it."
        }
    }
    $cfg = Get-Content -Path $Path -Raw | ConvertFrom-Json
    foreach ($section in 'target', 'auth') {
        if (-not $cfg.$section) { throw "Config is missing the '$section' section." }
    }
    foreach ($t in 'tenantId', 'subscriptionId', 'storageAccountName', 'fileSystem') {
        if (-not $cfg.target.$t) { throw "Config value target.$t is required." }
    }
    if (-not $cfg.target.rootPath) { $cfg.target | Add-Member -NotePropertyName rootPath -NotePropertyValue '/' -Force }
    return $cfg
}

function Invoke-WithRetry {
    <# Retries a read operation on transient errors (429/503/timeout) with exponential backoff. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [int]$MaxAttempts = 6,
        [int]$BaseDelayMs = 500,
        [string]$Activity = 'operation'
    )
    if (-not $MaxAttempts -or $MaxAttempts -lt 1) { $MaxAttempts = 6 }
    if ($null -eq $BaseDelayMs -or $BaseDelayMs -lt 0) { $BaseDelayMs = 500 }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try { return & $ScriptBlock }
        catch {
            $msg = $_.Exception.Message
            $transient = $msg -match '429|throttl|503|500|timeout|temporar|TooManyRequests|connection reset|operation timed'
            if ($attempt -ge $MaxAttempts -or -not $transient) { throw }
            $delay = [int]($BaseDelayMs * [math]::Pow(2, $attempt - 1))
            Write-ScanLog -Level WARN -Message ("{0}: attempt {1}/{2} failed ({3}); retrying in {4} ms" -f $Activity, $attempt, $MaxAttempts, $msg, $delay)
            Start-Sleep -Milliseconds $delay
        }
    }
}

function ConvertTo-SymbolicPermission {
    <# Normalizes an ADLS permission value to a symbolic string (e.g. 'r-x'). Handles symbolic
       strings, POSIX 9-char strings, and RolePermissions flag names ('Read, Execute'). #>
    param($Value)
    if ($null -eq $Value) { return '' }
    $s = "$Value".Trim()
    if ($s -match '^[rwxsStT-]{3}$' -or $s -match '^[rwxsStT-]{9}$') { return $s.ToLower() }
    $r = if ($s -match 'Read')    { 'r' } else { '-' }
    $w = if ($s -match 'Write')   { 'w' } else { '-' }
    $x = if ($s -match 'Execute') { 'x' } else { '-' }
    return "$r$w$x"
}

function Get-HeaderValue {
    <# Case-insensitive fetch of a single response header value from Invoke-WebRequest. #>
    param($Response, [Parameter(Mandatory)][string]$Name)
    if (-not $Response -or -not $Response.Headers) { return $null }
    foreach ($k in $Response.Headers.Keys) {
        if ($k -ieq $Name) {
            $v = $Response.Headers[$k]
            if ($v -is [array]) { return ($v -join ',') }
            return "$v"
        }
    }
    return $null
}

function ConvertFrom-XmsAcl {
    <# Parses an x-ms-acl header (e.g. 'user::rwx,group:oid:r-x,default:user::rwx') into ACE records. #>
    param([string]$Acl)
    $out = [System.Collections.Generic.List[object]]::new()
    if (-not $Acl) { return $out }
    foreach ($entry in ($Acl -split ',')) {
        if (-not $entry) { continue }
        $parts = $entry -split ':'
        $isDefault = $false
        if ($parts.Count -ge 1 -and $parts[0] -eq 'default') { $isDefault = $true; $parts = @($parts[1..($parts.Count - 1)]) }
        if ($parts.Count -ne 3) { continue }
        $out.Add([pscustomobject]@{
                scope       = if ($isDefault) { 'default' } else { 'access' }
                type        = $parts[0].ToLower()
                principalId = $parts[1]
                permissions = $parts[2]
            })
    }
    return $out
}

function Get-PathFacets {
    <# Splits a path into positional facets (level1..4 = dept/area/layer/project for this data shape). #>
    param([string]$Path)
    $clean = "$Path".Trim('/')
    $segs = if ($clean) { $clean -split '/' } else { @() }
    [pscustomobject]@{
        Path    = '/' + $clean
        Name    = if ($segs.Count) { $segs[-1] } else { '/' }
        Depth   = $segs.Count
        Level1  = if ($segs.Count -ge 1) { $segs[0] } else { $null }
        Level2  = if ($segs.Count -ge 2) { $segs[1] } else { $null }
        Level3  = if ($segs.Count -ge 3) { $segs[2] } else { $null }
        Level4  = if ($segs.Count -ge 4) { $segs[3] } else { $null }
    }
}

function Get-GroupKind {
    param([string]$DisplayName, $Config)
    foreach ($p in @($Config.groups.namePrefixes)) {
        if ($p -and $DisplayName -like "$p*") { return $p.TrimEnd('_') }
    }
    return 'other'
}

function Resolve-GroupReachable {
    # Recursive, memoized: does at least one USER end up an effective member of $Gid?
    # Membership flows child -> parent: a group's effective users = its direct users
    # PLUS the effective users of every group nested INTO it (its member-groups).
    param(
        [string]$Gid,
        [hashtable]$DirectUsers,
        [hashtable]$ChildrenOf,
        [hashtable]$Memo,
        $Stack
    )
    if ($Memo.ContainsKey($Gid)) { return $Memo[$Gid] }
    if ($Stack.Contains($Gid)) { return $false }   # cycle guard
    $result = $false
    if ($DirectUsers.ContainsKey($Gid)) {
        $result = $true
    }
    elseif ($ChildrenOf.ContainsKey($Gid)) {
        [void]$Stack.Add($Gid)
        foreach ($child in $ChildrenOf[$Gid]) {
            if (Resolve-GroupReachable -Gid $child -DirectUsers $DirectUsers -ChildrenOf $ChildrenOf -Memo $Memo -Stack $Stack) {
                $result = $true
                break
            }
        }
        [void]$Stack.Remove($Gid)
    }
    $Memo[$Gid] = $result
    return $result
}

function Get-ReachableGroupMap {
    # Returns a hashtable { groupId -> [bool] reachable-by-at-least-one-user (transitively) }.
    param($Memberships, $Nesting)
    $directUsers = @{}
    $childrenOf = @{}
    foreach ($m in @($Memberships)) {
        if ($m.memberType -eq 'user') {
            $directUsers[$m.groupId] = $true
        }
        elseif ($m.memberType -eq 'group') {
            if (-not $childrenOf.ContainsKey($m.groupId)) { $childrenOf[$m.groupId] = New-Object System.Collections.Generic.List[string] }
            $childrenOf[$m.groupId].Add($m.memberId)
        }
    }
    foreach ($n in @($Nesting)) {
        if (-not $childrenOf.ContainsKey($n.parentGroupId)) { $childrenOf[$n.parentGroupId] = New-Object System.Collections.Generic.List[string] }
        $childrenOf[$n.parentGroupId].Add($n.childGroupId)
    }
    $memo = @{}
    $ids = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $directUsers.Keys) { [void]$ids.Add($k) }
    foreach ($k in $childrenOf.Keys) {
        [void]$ids.Add($k)
        foreach ($c in $childrenOf[$k]) { [void]$ids.Add($c) }
    }
    foreach ($gid in $ids) {
        [void](Resolve-GroupReachable -Gid $gid -DirectUsers $directUsers -ChildrenOf $childrenOf -Memo $memo -Stack (New-Object System.Collections.Generic.HashSet[string]))
    }
    return $memo
}

function Get-GroupRole {
    # Behavioural (naming-independent) classification of a group's function.
    param([bool]$OnAce, [bool]$HasMembers)
    if ($OnAce -and $HasMembers) { return 'hybrid' }
    if ($OnAce) { return 'access' }
    if ($HasMembers) { return 'role' }
    return 'unused'
}

function Get-GroupStatus {
    # Effective-access-aware liveness. 'unreachable' = carries a folder grant but no user reaches it.
    param([string]$Role, [bool]$OnAce, [bool]$Reachable)
    if ($Role -eq 'unused') { return 'unused' }
    if ($OnAce -and -not $Reachable) { return 'unreachable' }
    return 'active'
}

function Write-Jsonl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$InputObject
    )
    ($InputObject | ConvertTo-Json -Depth 8 -Compress) |
        ForEach-Object { [System.IO.File]::AppendAllText($Path, $_ + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false))) }
}

function Test-PathFilter {
    param([string]$Path, [string[]]$Include, [string[]]$Exclude)
    if ($Exclude) { foreach ($e in $Exclude) { if ($e -and $Path.StartsWith($e)) { return $false } } }
    if ($Include -and $Include.Count) {
        foreach ($i in $Include) { if ($i -and $Path.StartsWith($i)) { return $true } }
        return $false
    }
    return $true
}

function Resolve-RepoPath {
    param([string]$Path, [string]$RepoRoot)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $RepoRoot ($Path -replace '^\.[\\/]', ''))
}
