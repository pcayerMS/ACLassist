#Requires -Version 7.0
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

function Get-ScanConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Config not found: $Path`nCopy config/config.sample.json to config/config.json and edit it."
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
    $r = ($s -match 'Read')    ? 'r' : '-'
    $w = ($s -match 'Write')   ? 'w' : '-'
    $x = ($s -match 'Execute') ? 'x' : '-'
    return "$r$w$x"
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

function Write-Jsonl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$InputObject
    )
    ($InputObject | ConvertTo-Json -Depth 8 -Compress) | Add-Content -Path $Path -Encoding utf8
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
