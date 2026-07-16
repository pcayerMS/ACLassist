#Requires -Version 7.0
<#
  Connect-Target.ps1 — establishes READ-ONLY sessions to Azure, ADLS, and Microsoft Graph.
  Uses only client-side context cmdlets + sign-in. Nothing here mutates Azure or Entra.
#>

function Connect-ScanTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $t = $Config.target

    # --- Azure (interactive sign-in; used for the data plane and RBAC read) ---
    $az = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $az) {
        Write-ScanLog INFO 'Signing in to Azure (interactive)...'
        Connect-AzAccount -Tenant $t.tenantId -Subscription $t.subscriptionId -ErrorAction Stop | Out-Null
    }
    try {
        Set-AzContext -Subscription $t.subscriptionId -ErrorAction Stop | Out-Null
    }
    catch {
        Write-ScanLog INFO 'Selecting subscription requires sign-in...'
        Connect-AzAccount -Tenant $t.tenantId -Subscription $t.subscriptionId -ErrorAction Stop | Out-Null
        Set-AzContext -Subscription $t.subscriptionId -ErrorAction Stop | Out-Null
    }
    $az = Get-AzContext
    Write-ScanLog OK ("Azure context: {0}  (sub {1})" -f $az.Account.Id, $t.subscriptionId)

    # --- Storage data-plane context (READ) ---
    if ($Config.auth.mode -eq 'sas') {
        if (-not $Config.auth.sasToken) { throw 'auth.mode = sas but auth.sasToken is empty. Provide a read+list SAS.' }
        $sc = New-AzStorageContext -StorageAccountName $t.storageAccountName -SasToken $Config.auth.sasToken
        Write-ScanLog OK 'Storage context via SAS (read/list).'
    }
    else {
        $sc = New-AzStorageContext -StorageAccountName $t.storageAccountName -UseConnectedAccount
        Write-ScanLog OK 'Storage context via OAuth (connected account).'
    }

    # --- Microsoft Graph (READ scopes) ---
    $scopes = @($Config.auth.graphScopes)
    if (-not $scopes -or $scopes.Count -eq 0) {
        $scopes = @('Directory.Read.All', 'Group.Read.All', 'GroupMember.Read.All', 'User.Read.All')
    }
    $mg = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $mg -or -not $mg.Account) {
        Write-ScanLog INFO 'Signing in to Microsoft Graph (interactive, read scopes)...'
        Connect-MgGraph -TenantId $t.tenantId -Scopes $scopes -NoWelcome -ErrorAction Stop
    }
    $mg = Get-MgContext
    Write-ScanLog OK ("Graph context: {0}" -f $mg.Account)

    return [pscustomobject]@{
        StorageContext = $sc
        Account        = $az.Account.Id
        TenantId       = $t.tenantId
        SubscriptionId = $t.subscriptionId
        GraphAccount   = $mg.Account
    }
}
