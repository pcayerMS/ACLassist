#
# ReadOnly.Allowlist.psd1
#
# The AUTHORITATIVE list of Azure/Entra operations the engine is permitted to call.
# Every one is a read/list operation, except the client-side context cmdlets (which create or select
# only in-memory objects and change nothing remotely). A compliance check can assert that the engine
# scripts invoke no Az.*/Mg* command outside AllowedCmdlets.
#
@{
    Description = 'The only Azure/Entra operations the engine may perform. All are read-only w.r.t. Azure and Entra.'

    # Read/list operations against Azure resources, ADLS data, and the directory.
    AllowedCmdlets = @(
        # Authentication / context (no remote mutation)
        'Connect-AzAccount',
        'Disconnect-AzAccount',
        'Get-AzContext',
        'Set-AzContext',
        'Connect-MgGraph',
        'Disconnect-MgGraph',
        'Get-MgContext',
        # Storage client context (creates an in-memory object only)
        'New-AzStorageContext',
        # ADLS Gen2 data-plane reads use the DFS REST API (GET List Paths, HEAD getAccessControl)
        # with a token from Get-AzAccessToken, or a read+list SAS. See ReadOnlyRest below.
        'Get-AzAccessToken',
        # Azure RBAC read
        'Get-AzRoleAssignment',
        # Microsoft Graph read
        'Get-MgGroup',
        'Get-MgGroupMember',
        'Get-MgGroupTransitiveMember',
        'Get-MgUser'
    )

    # Allowlisted cmdlets whose verb looks mutating but which only touch CLIENT-SIDE state.
    ClientSideContextCmdlets = @(
        'Connect-AzAccount',
        'Disconnect-AzAccount',
        'Set-AzContext',
        'Connect-MgGraph',
        'Disconnect-MgGraph',
        'New-AzStorageContext'
    )

    # Verbs that must NEVER appear on an Az.* or Mg* command in this engine (guards against remote writes).
    # Applies to Azure/Entra commands only — ordinary local file I/O is permitted.
    ForbiddenVerbs = @(
        'New', 'Set', 'Update', 'Remove', 'Add', 'Move', 'Rename',
        'Clear', 'Disable', 'Enable', 'Grant', 'Revoke', 'Deny', 'Restore', 'Invoke'
    )

    # Read-only DFS REST calls used for the ADLS data plane (never PUT/PATCH/POST/DELETE).
    ReadOnlyRest = @(
        'GET  https://<account>.dfs.core.windows.net/<filesystem>?resource=filesystem&recursive=true  (List Paths)',
        'HEAD https://<account>.dfs.core.windows.net/<filesystem>/<path>?action=getAccessControl       (read ACL)'
    )

    Notes = @(
        'AllowedCmdlets is authoritative; ForbiddenVerbs is a guard for Az.*/Mg* commands only.',
        'ADLS data-plane reads use Invoke-WebRequest with GET/HEAD only (see ReadOnlyRest) - no mutating verbs.',
        'The exceptions in ClientSideContextCmdlets create/select in-memory objects and change nothing remotely.',
        'Writing local artifacts (e.g. data/inventory.json) is not an Azure/Entra mutation and is allowed.',
        'There is no remediation/apply code in Phase 1.'
    )
}
