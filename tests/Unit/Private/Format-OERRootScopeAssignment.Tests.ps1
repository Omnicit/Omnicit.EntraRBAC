BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Format-OERRootScopeAssignment' {
    # BL-126: the one order and the one list text of the role assignments at the Azure root scope that
    # Get-OERInventory and Export-OERInventory name in their warnings. No id below is version-4 shaped.
    BeforeAll {
        function New-Row {
            param([string]$Id, [string]$Role, [string]$Principal, [string]$PrincipalType)
            [PSCustomObject]@{ RoleAssignmentId = $Id; Role = $Role; Principal = $Principal; PrincipalType = $PrincipalType }
        }
        function Invoke-Format {
            param([object[]]$Rows)
            InModuleScope $script:moduleName -Parameters @{ Rows = $Rows } {
                param($Rows)
                Format-OERRootScopeAssignment -Assignment $Rows
            }
        }
    }

    It 'returns no row and an empty text for no row' {
        $Result = Invoke-Format -Rows @()
        @($Result.Assignments).Count | Should -Be 0
        $Result.Text | Should -BeExactly ''
    }

    It 'lists one row as the quoted role for the quoted principal, with the type in parentheses' {
        $Result = Invoke-Format -Rows @(New-Row -Id '/providers/Microsoft.Authorization/roleAssignments/cccc3333-0000-0000-0000-000000000001' -Role 'User Access Administrator' -Principal 'person1@example.com' -PrincipalType 'User')
        $Result.Text | Should -BeExactly "'User Access Administrator' for 'person1@example.com' (User)"
        @($Result.Assignments).Count | Should -Be 1
        @($Result.Assignments)[0].RoleAssignmentId | Should -BeExactly '/providers/Microsoft.Authorization/roleAssignments/cccc3333-0000-0000-0000-000000000001'
    }

    It 'writes no parenthesis when the principal type is unknown' {
        (Invoke-Format -Rows @(New-Row -Id 'ra-1' -Role 'Owner' -Principal 'Ops' -PrincipalType '')).Text | Should -BeExactly "'Owner' for 'Ops'"
        (Invoke-Format -Rows @(New-Row -Id 'ra-1' -Role 'Owner' -Principal 'Ops' -PrincipalType $null)).Text | Should -BeExactly "'Owner' for 'Ops'"
    }

    It 'sorts by role, then principal, then role assignment id, ordinal and without regard to letter case, and joins the rows with ''; ''' {
        # Ordinal: 'ab' sorts before 'a_b', since '_' follows the letters once both are upper case.
        # A culture comparison puts 'a_b' first, so the first two rows pin the comparison as ordinal.
        $Result = Invoke-Format -Rows @(
            New-Row -Id 'ra-5' -Role 'a_b' -Principal 'p' -PrincipalType 'User'
            New-Row -Id 'ra-4' -Role 'AB' -Principal 'p' -PrincipalType 'User'
            New-Row -Id 'ra-3' -Role 'Owner' -Principal 'zeta' -PrincipalType 'Group'
            New-Row -Id 'ra-2' -Role 'owner' -Principal 'Alpha' -PrincipalType ''
            New-Row -Id 'RA-1' -Role 'Owner' -Principal 'alpha' -PrincipalType ''
        )
        @($Result.Assignments | ForEach-Object { $_.RoleAssignmentId }) | Should -Be @('ra-4', 'ra-5', 'RA-1', 'ra-2', 'ra-3')
        $Result.Text | Should -BeExactly "'AB' for 'p' (User); 'a_b' for 'p' (User); 'Owner' for 'alpha'; 'owner' for 'Alpha'; 'Owner' for 'zeta' (Group)"
    }

    It 'lists an assignment read at several scopes once, on its role assignment id without regard to letter case' {
        $Result = Invoke-Format -Rows @(
            New-Row -Id '/providers/Microsoft.Authorization/roleAssignments/cccc3333-0000-0000-0000-00000000000a' -Role 'Owner' -Principal 'Ops' -PrincipalType 'Group'
            New-Row -Id '/PROVIDERS/Microsoft.Authorization/roleAssignments/CCCC3333-0000-0000-0000-00000000000A' -Role 'Owner' -Principal 'Ops' -PrincipalType 'Group'
            New-Row -Id '/providers/Microsoft.Authorization/roleAssignments/cccc3333-0000-0000-0000-00000000000b' -Role 'Owner' -Principal 'Ops' -PrincipalType 'Group'
        )
        # Two assignments, not three: the second row is the first one read again. The third is another
        # assignment that carries the same role and principal name, so it stays.
        @($Result.Assignments | ForEach-Object { $_.RoleAssignmentId }) | Should -Be @(
            '/providers/Microsoft.Authorization/roleAssignments/cccc3333-0000-0000-0000-00000000000a'
            '/providers/Microsoft.Authorization/roleAssignments/cccc3333-0000-0000-0000-00000000000b'
        )
        $Result.Text | Should -BeExactly "'Owner' for 'Ops' (Group); 'Owner' for 'Ops' (Group)"
    }

    It 'lists two rows without a role assignment id once when they name the same role and principal' {
        $Result = Invoke-Format -Rows @(
            New-Row -Id '' -Role 'Owner' -Principal 'Ops' -PrincipalType 'Group'
            New-Row -Id '' -Role 'owner' -Principal 'OPS' -PrincipalType 'Group'
            New-Row -Id '' -Role 'Owner' -Principal 'Other' -PrincipalType 'Group'
        )
        $Result.Text | Should -BeExactly "'Owner' for 'Ops' (Group); 'Owner' for 'Other' (Group)"
    }

    It 'skips a null entry' {
        $Result = Invoke-Format -Rows @($null, (New-Row -Id 'ra-1' -Role 'Owner' -Principal 'Ops' -PrincipalType 'Group'), $null)
        @($Result.Assignments).Count | Should -Be 1
        $Result.Text | Should -BeExactly "'Owner' for 'Ops' (Group)"
    }
}
