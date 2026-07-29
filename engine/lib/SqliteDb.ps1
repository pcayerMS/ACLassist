#Requires -Version 5.1
<#
  SqliteDb.ps1 — thin, dependency-free data-access layer over the bundled sqlite3.exe.
  READ/local only: it creates and populates the assessment database from CSV staging files and runs the
  deterministic analysis SQL. All data enters via typed CSV .import (never string-built INSERTs), and every
  analysis statement is fixed SQL shipped in engine/sql/*.sql — so there is no SQL-injection surface and no
  chance of value-quoting corruption. Works identically on Windows PowerShell 5.1 and PowerShell 7.
#>

function Resolve-Sqlite3Path {
    [CmdletBinding()]
    param($Config, [Parameter(Mandatory)][string]$RepoRoot)
    if ($Config -and $Config.tools -and $Config.tools.sqlite3Path) {
        if (Test-Path $Config.tools.sqlite3Path) { return (Resolve-Path $Config.tools.sqlite3Path).Path }
        throw "config tools.sqlite3Path is set but not found: $($Config.tools.sqlite3Path)"
    }
    $bundled = Join-Path $RepoRoot 'engine/tools/sqlite3.exe'
    if (Test-Path $bundled) { return $bundled }
    $cmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "sqlite3 not found. Expected bundled engine/tools/sqlite3.exe, or config tools.sqlite3Path, or sqlite3 on PATH."
}

function Invoke-SqliteText {
    # Pipe SQL/dot-commands to sqlite3 via stdin; returns stdout lines. Throws on non-zero exit.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sqlite, [Parameter(Mandatory)][string]$DbPath, [Parameter(Mandatory)][string]$Sql, [switch]$AsJson)
    $cliArgs = @('-batch', '-bail')
    if ($AsJson) { $cliArgs += '-json' }
    $cliArgs += $DbPath
    # Windows PowerShell pipes native commands through the OEM code page, which turns every non-ASCII
    # character into '?' in BOTH directions. SQLite is UTF-8 throughout, so force UTF-8 or accented
    # group names, UPNs and folder names silently corrupt.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $prevConsole = $null
    try { $prevConsole = [Console]::OutputEncoding; [Console]::OutputEncoding = $utf8 } catch { $prevConsole = $null }
    $OutputEncoding = $utf8
    try {
        $out = $Sql | & $Sqlite @cliArgs 2>&1
    }
    finally {
        if ($prevConsole) { try { [Console]::OutputEncoding = $prevConsole } catch { } }
    }
    if ($LASTEXITCODE -ne 0) { throw ("sqlite3 failed (exit {0}): {1}" -f $LASTEXITCODE, ($out -join "`n")) }
    return $out
}

function New-AclDatabase {
    # (Re)create the database file from schema.sql.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sqlite, [Parameter(Mandatory)][string]$DbPath, [Parameter(Mandatory)][string]$SchemaSqlPath)
    $dir = Split-Path -Parent $DbPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path $DbPath) { Remove-Item $DbPath -Force }
    foreach ($ext in '-wal', '-shm') { $p = "$DbPath$ext"; if (Test-Path $p) { Remove-Item $p -Force } }
    Invoke-AclSqlFile -Sqlite $Sqlite -DbPath $DbPath -SqlPath $SchemaSqlPath
}

function Import-AclCsvs {
    # Bulk-load one CSV per table (headered) from a staging dir. Column order must match the schema.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sqlite, [Parameter(Mandatory)][string]$DbPath, [Parameter(Mandatory)][string]$StagingDir, [Parameter(Mandatory)][string[]]$Tables)
    $lines = @('.mode csv')
    foreach ($t in $Tables) {
        $csv = Join-Path $StagingDir "$t.csv"
        if (Test-Path $csv) {
            $p = ((Resolve-Path $csv).Path -replace '\\', '/')
            $lines += ".import --skip 1 '$p' $t"
        }
    }
    [void](Invoke-SqliteText -Sqlite $Sqlite -DbPath $DbPath -Sql ($lines -join "`n"))
}

function Invoke-AclSqlFile {
    # Let sqlite3 read the .sql file itself. Never round-trip SQL text through PowerShell: Get-Content
    # would decode a BOM-free UTF-8 file as ANSI, and the native-command pipe would then map anything
    # non-ASCII to '?'. sqlite3 reads UTF-8 natively, so this is the only lossless path.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sqlite, [Parameter(Mandatory)][string]$DbPath, [Parameter(Mandatory)][string]$SqlPath)
    $p = ((Resolve-Path $SqlPath).Path -replace '\\', '/')
    [void](Invoke-SqliteText -Sqlite $Sqlite -DbPath $DbPath -Sql (".read '" + $p + "'"))
}

function Invoke-AclAnalysis {
    # Run the deterministic analysis SQL (metrics, closures, snapshot).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sqlite, [Parameter(Mandatory)][string]$DbPath, [Parameter(Mandatory)][string]$AnalyzeSqlPath)
    Invoke-AclSqlFile -Sqlite $Sqlite -DbPath $DbPath -SqlPath $AnalyzeSqlPath
}

function Get-AclQuery {
    # Run a SELECT and return objects (via sqlite3 -json).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sqlite, [Parameter(Mandatory)][string]$DbPath, [Parameter(Mandatory)][string]$Sql)
    $out = Invoke-SqliteText -Sqlite $Sqlite -DbPath $DbPath -Sql $Sql -AsJson
    $text = ($out -join "`n").Trim()
    if (-not $text) { return @() }
    return ($text | ConvertFrom-Json)
}

function Write-AclCsv {
    # BOM-free UTF-8, RFC4180-quoted CSV with columns in the given (schema) order.
    [CmdletBinding()]
    param([object[]]$Rows, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Columns)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(($Columns -join ',')); [void]$sb.Append("`n")
    foreach ($r in @($Rows)) {
        $cells = foreach ($c in $Columns) {
            $v = $r.$c
            if ($null -eq $v) { '' }
            else {
                $s = [string]$v
                if ($s.IndexOfAny([char[]]@('"', ',', "`r", "`n")) -ge 0) { '"' + ($s -replace '"', '""') + '"' } else { $s }
            }
        }
        [void]$sb.Append(($cells -join ',')); [void]$sb.Append("`n")
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
}
