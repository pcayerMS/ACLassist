#Requires -Version 5.1
<#
  Connect-Target.ps1 — establishes READ-ONLY sessions to Azure, ADLS, and Microsoft Graph.
  Uses only client-side context cmdlets + sign-in. Nothing here mutates Azure or Entra.
#>

function Connect-ScanTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $t = $Config.target
    $acctParam = @{}
    if ($Config.auth.loginHint) { $acctParam['AccountId'] = $Config.auth.loginHint }

    # --- Azure (interactive sign-in; used for the data-plane token + RBAC read) ---
    $az = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $az) {
        Write-ScanLog INFO 'Signing in to Azure (interactive)...'
        Connect-AzAccount -Tenant $t.tenantId -Subscription $t.subscriptionId @acctParam -ErrorAction Stop | Out-Null
    }
    try {
        Set-AzContext -Subscription $t.subscriptionId -ErrorAction Stop | Out-Null
    }
    catch {
        Write-ScanLog INFO 'Selecting subscription requires sign-in...'
        Connect-AzAccount -Tenant $t.tenantId -Subscription $t.subscriptionId @acctParam -ErrorAction Stop | Out-Null
        Set-AzContext -Subscription $t.subscriptionId -ErrorAction Stop | Out-Null
    }
    $az = Get-AzContext
    Write-ScanLog OK ("Azure context: {0}  (sub {1})" -f $az.Account.Id, $t.subscriptionId)

    # Data-plane reads use an OAuth bearer token (Get-AzAccessToken) in Invoke-AclScan - no SAS, no account keys.

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
        Account        = $az.Account.Id
        TenantId       = $t.tenantId
        SubscriptionId = $t.subscriptionId
        GraphAccount   = $mg.Account
    }
}
