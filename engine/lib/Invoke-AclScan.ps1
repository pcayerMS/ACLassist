#Requires -Version 5.1
<#
  Invoke-AclScan.ps1 — READ-ONLY enumeration of ADLS Gen2 folders + ACLs via the DFS REST API.
  Uses GET (List Paths) + HEAD (getAccessControl) only, authenticated with an Entra OAuth bearer token
  (Get-AzAccessToken) or a read+list SAS. This avoids the Az.Storage -UseConnectedAccount cmdlet path,
  yields clean symbolic ACL strings, and can read the filesystem root ACL. Streams ACE records to JSONL.
#>

function Invoke-AclScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$AceJsonlPath
    )

    $acct = $Config.target.storageAccountName
    $fs = $Config.target.fileSystem
    $root = "$($Config.target.rootPath)".Trim('/')
    $base = "https://$acct.dfs.core.windows.net"
    $ver = '2025-07-05'
    $maxAttempts = $Config.scan.retry.maxAttempts
    $baseDelay = $Config.scan.retry.baseDelayMs
    $inc = $Config.scan.pathFilters.includePrefixes
    $exc = $Config.scan.pathFilters.excludePrefixes
    $includeDefault = [bool]$Config.scan.includeDefaultAces

    Write-ScanLog OK ("ADLS scan (REST) starting: {0} : /{1}" -f $fs, $root)

    # --- auth: OAuth bearer (interactive) or read+list SAS ---
    $headers = @{ 'x-ms-version' = $ver }
    $authQ = ''
    if ($Config.auth.mode -eq 'sas') {
        if (-not $Config.auth.sasToken) { throw 'auth.mode = sas but auth.sasToken is empty. Provide a read+list SAS.' }
        $authQ = '&' + $Config.auth.sasToken.TrimStart('?')
        Write-ScanLog OK 'Data-plane auth: SAS (read/list).'
    }
    else {
        $t = Get-AzAccessToken -ResourceUrl 'https://storage.azure.com'
        $tok = if ($t.Token -is [securestring]) { [System.Net.NetworkCredential]::new('', $t.Token).Password } else { $t.Token }
        $headers['Authorization'] = "Bearer $tok"
        Write-ScanLog OK 'Data-plane auth: OAuth bearer (Get-AzAccessToken).'
    }

    # Fresh JSONL sink.
    if (Test-Path $AceJsonlPath) { Remove-Item $AceJsonlPath -Force }
    New-Item -ItemType File -Path $AceJsonlPath -Force | Out-Null

    # --- 1) List Paths (recursive, paginated) ---
    $metaByName = @{}
    $names = [System.Collections.Generic.List[string]]::new()
    $cont = ''
    do {
        $dirQ = if ($root) { "&directory=$([uri]::EscapeDataString($root))" } else { '' }
        $contQ = if ($cont) { "&continuation=$([uri]::EscapeDataString($cont))" } else { '' }
        $uri = "$base/$fs`?resource=filesystem&recursive=true&maxResults=5000$dirQ$contQ$authQ"
        $resp = Invoke-WithRetry -Activity 'DFS List Paths' -MaxAttempts $maxAttempts -BaseDelayMs $baseDelay -ScriptBlock {
            try { Invoke-WebRequest -Method GET -Uri $uri -Headers $headers -UseBasicParsing }
            catch {
                if ("$($_.Exception.Message)" -match '403|AuthorizationFailure|not authorized') { Write-DataPlaneAccessHint -Config $Config }
                throw
            }
        }
        $cont = Get-HeaderValue $resp 'x-ms-continuation'
        foreach ($p in ($resp.Content | ConvertFrom-Json).paths) { $metaByName[$p.name] = $p; $names.Add($p.name) }
        Write-ScanLog INFO ("  listed {0} paths so far" -f $names.Count)
    } while ($cont)

    # --- 2) getAccessControl per path (+ the filesystem root when scanning from /) ---
    $folders = [System.Collections.Generic.List[object]]::new()
    $principalRefs = @{}
    $aceCount = 0
    $itemCount = 0

    $targets = [System.Collections.Generic.List[string]]::new()
    if (-not $root) { $targets.Add('') }   # container root ACL (addressable via REST)
    foreach ($n in $names) { $targets.Add($n) }
    $total = $targets.Count

    foreach ($rel in $targets) {
        $facets = Get-PathFacets -Path $rel
        if ($rel -and -not (Test-PathFilter -Path $facets.Path -Include $inc -Exclude $exc)) { continue }
        $itemCount++
        $meta = if ($rel) { $metaByName[$rel] } else { $null }

        $aclStr = $null
        try {
            $encPath = ($rel -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
            $uri = "$base/$fs/$encPath`?action=getAccessControl&upn=false$authQ"
            $r = Invoke-WithRetry -Activity ("getAccessControl {0}" -f $facets.Path) -MaxAttempts $maxAttempts -BaseDelayMs $baseDelay -ScriptBlock {
                try { Invoke-WebRequest -Method HEAD -Uri $uri -Headers $headers -UseBasicParsing }
                catch {
                    if ("$($_.Exception.Message)" -match '403|AuthorizationFailure|not authorized') { Write-DataPlaneAccessHint -Config $Config }
                    throw
                }
            }
            $aclStr = Get-HeaderValue $r 'x-ms-acl'
        }
        catch { Write-ScanLog WARN ("getAccessControl failed for {0}: {1}" -f $facets.Path, $_.Exception.Message) }

        $isDir = if ($meta) { "$($meta.isDirectory)" -eq 'true' } else { $true }
        $folders.Add([pscustomobject]@{
                id              = $facets.Path
                path            = $facets.Path
                name            = $facets.Name
                depth           = $facets.Depth
                isDirectory     = $isDir
                level1          = $facets.Level1
                level2          = $facets.Level2
                level3          = $facets.Level3
                level4          = $facets.Level4
                owner           = if ($meta) { "$($meta.owner)" } else { '' }
                ownerGroup      = if ($meta) { "$($meta.group)" } else { '' }
                basePermissions = if ($meta) { "$($meta.permissions)" } else { '' }
            })

        foreach ($ace in (ConvertFrom-XmsAcl $aclStr)) {
            if ($ace.scope -eq 'default' -and -not $includeDefault) { continue }
            Write-Jsonl -Path $AceJsonlPath -InputObject ([pscustomobject]@{
                    folderId      = $facets.Path
                    folderPath    = $facets.Path
                    principalId   = $ace.principalId
                    principalType = $ace.type
                    scope         = $ace.scope
                    permissions   = $ace.permissions
                    isNamed       = [bool]$ace.principalId
                })
            $aceCount++
            if ($ace.principalId -and $ace.type -in @('user', 'group')) { $principalRefs[$ace.principalId] = $ace.type }
        }

        if ($itemCount % 100 -eq 0) { Write-ScanLog INFO ("  ACLs {0}/{1}, {2} ACEs" -f $itemCount, $total, $aceCount) }
    }

    Write-ScanLog OK ("ADLS scan complete: {0} items, {1} ACEs, {2} named principals" -f $itemCount, $aceCount, $principalRefs.Count)
    return [pscustomobject]@{
        Folders       = $folders
        AceCount      = $aceCount
        ItemCount     = $itemCount
        PrincipalRefs = $principalRefs
        AceJsonlPath  = $AceJsonlPath
    }
}
