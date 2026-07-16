#Requires -Version 7.0
<#
  Invoke-AclScan.ps1 — READ-ONLY enumeration of ADLS Gen2 folders + ACLs.
  Reads with Get-AzDataLakeGen2ChildItem / Get-AzDataLakeGen2Item only. Streams ACE records to JSONL.
  Note: the container root '/' ACL is not addressable by the cmdlets and is not captured in M1;
  every non-root folder ACL is captured.
#>

function Invoke-AclScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$StorageContext,
        [Parameter(Mandatory)][string]$FileSystem,
        [string]$RootPath = '/',
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$AceJsonlPath
    )

    Write-ScanLog OK ("ADLS scan starting: {0} : {1}" -f $FileSystem, $RootPath)

    # Fresh JSONL sink.
    if (Test-Path $AceJsonlPath) { Remove-Item $AceJsonlPath -Force }
    New-Item -ItemType File -Path $AceJsonlPath -Force | Out-Null

    $inc = $Config.scan.pathFilters.includePrefixes
    $exc = $Config.scan.pathFilters.excludePrefixes
    $includeDefault = [bool]$Config.scan.includeDefaultAces
    $includeAccess = ($null -eq $Config.scan.includeAccessAces) -or [bool]$Config.scan.includeAccessAces
    $maxAttempts = $Config.scan.retry.maxAttempts
    $baseDelay = $Config.scan.retry.baseDelayMs

    $folders = [System.Collections.Generic.List[object]]::new()
    $principalRefs = @{}
    $aceCount = 0
    $itemCount = 0

    $rootArg = if ($RootPath -in @('/', '', $null)) { $null } else { $RootPath.Trim('/') }
    $listParams = @{ Context = $StorageContext; FileSystem = $FileSystem; Recurse = $true; FetchProperty = $true }
    if ($rootArg) { $listParams['Path'] = $rootArg }

    $items = Invoke-WithRetry -Activity 'ADLS recurse-list' -MaxAttempts $maxAttempts -BaseDelayMs $baseDelay -ScriptBlock {
        Get-AzDataLakeGen2ChildItem @listParams
    }

    foreach ($item in $items) {
        $facets = Get-PathFacets -Path $item.Path
        if (-not (Test-PathFilter -Path $facets.Path -Include $inc -Exclude $exc)) { continue }
        $itemCount++

        $acl = $item.ACL
        if (-not $acl) {
            try {
                $full = Invoke-WithRetry -Activity ("get-item {0}" -f $facets.Path) -MaxAttempts $maxAttempts -BaseDelayMs $baseDelay -ScriptBlock {
                    Get-AzDataLakeGen2Item -Context $StorageContext -FileSystem $FileSystem -Path $item.Path
                }
                $acl = $full.ACL
            }
            catch { Write-ScanLog WARN ("ACL fetch failed for {0}: {1}" -f $facets.Path, $_.Exception.Message) }
        }

        $folders.Add([pscustomobject]@{
                id              = $facets.Path
                path            = $facets.Path
                name            = $facets.Name
                depth           = $facets.Depth
                isDirectory     = [bool]$item.IsDirectory
                level1          = $facets.Level1
                level2          = $facets.Level2
                level3          = $facets.Level3
                level4          = $facets.Level4
                owner           = "$($item.Owner)"
                ownerGroup      = "$($item.Group)"
                basePermissions = (ConvertTo-SymbolicPermission $item.Permissions)
            })

        foreach ($e in @($acl)) {
            if (-not $e) { continue }
            $scope = if ($e.DefaultScope) { 'default' } else { 'access' }
            if ($scope -eq 'default' -and -not $includeDefault) { continue }
            if ($scope -eq 'access' -and -not $includeAccess) { continue }

            $ptype = "$($e.AccessControlType)".ToLower()
            $principal = "$($e.EntityId)"
            Write-Jsonl -Path $AceJsonlPath -InputObject ([pscustomobject]@{
                    folderId      = $facets.Path
                    folderPath    = $facets.Path
                    principalId   = $principal
                    principalType = $ptype
                    scope         = $scope
                    permissions   = (ConvertTo-SymbolicPermission $e.Permissions)
                    isNamed       = [bool]$principal
                })
            $aceCount++
            if ($principal -and $ptype -in @('user', 'group')) { $principalRefs[$principal] = $ptype }
        }

        if ($itemCount % 100 -eq 0) { Write-ScanLog INFO ("  scanned {0} items, {1} ACEs" -f $itemCount, $aceCount) }
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
