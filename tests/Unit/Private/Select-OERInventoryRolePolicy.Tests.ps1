BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # BL-107. The selection is pure: policies (as Get-OERInventoryRolePolicy emits them), the role
    # assignments and eligibilities read, and the scopes whose reads failed. No id below is
    # version-4 shaped.
    $script:SelSub = '/subscriptions/11111111-1111-1111-1111-111111111111'
    $script:SelRg = "$script:SelSub/resourceGroups/rg-app"
    $script:SelMg = '/providers/Microsoft.Management/managementGroups/mg-parent'
    $script:SelOtherSub = '/subscriptions/22222222-2222-2222-2222-222222222222'
    $script:SelSubRoleDef = "$script:SelSub/providers/Microsoft.Authorization/roleDefinitions"
    $script:SelTenantRoleDef = '/providers/Microsoft.Authorization/roleDefinitions'

    # A candidate in the shape Get-OERInventoryRolePolicy emits. The entry's role is the name a test
    # reads back to tell what was kept.
    function New-TestPolicy {
        param([string]$Name, [string]$Scope, [string]$RoleGuid, $Modified = $false, [string]$RoleDefinitionId)
        if (-not $PSBoundParameters.ContainsKey('RoleDefinitionId')) {
            $RoleDefinitionId = if ($RoleGuid) { "$script:SelSubRoleDef/$RoleGuid" } else { '' }
        }
        [PSCustomObject]@{
            Entry            = [PSCustomObject]@{ scope = $Scope; role = $Name }
            Scope            = $Scope
            RoleDefinitionId = $RoleDefinitionId
            Modified         = $Modified
        }
    }
    # A role assignment or eligibility fact: a scope and a role definition id.
    function New-TestFact {
        param([string]$Scope, [string]$RoleDefinitionId)
        [PSCustomObject]@{ Scope = $Scope; RoleDefinitionId = $RoleDefinitionId }
    }
    function Invoke-TestSelect {
        param([object[]]$Policy = @(), [object[]]$Assignment = @(), [object[]]$Eligibility = @(), [string[]]$UnreadScope = @())
        $Output = @(InModuleScope Omnicit.EntraRBAC -Parameters @{ P = $Policy; A = $Assignment; E = $Eligibility; U = $UnreadScope } {
                param($P, $A, $E, $U)
                Select-OERInventoryRolePolicy -Policy $P -Assignment $A -Eligibility $E -UnreadScope $U
            })
        # One object and nothing else on the output stream.
        $Output.Count | Should -Be 1
        $Output[0]
    }
    # The role names of the kept entries, in order, joined with commas (so a failure prints the list).
    function Get-KeptName {
        param($Result)
        @(@($Result.Kept) | ForEach-Object { $_.role }) -join ','
    }
    # The unjudged scopes, in order, joined with commas.
    function Get-UnjudgedText {
        param($Result)
        @($Result.UnjudgedScopes) -join ','
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Select-OERInventoryRolePolicy' {
    It 'keeps the policy of a role with an active assignment exactly at the scope' {
        $Result = Invoke-TestSelect `
            -Policy @(New-TestPolicy -Name 'Assigned' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000a') `
            -Assignment @(New-TestFact -Scope $script:SelSub -RoleDefinitionId "$script:SelSubRoleDef/aaaaaaaa-0000-0000-0000-00000000000a")
        Get-KeptName $Result | Should -BeExactly 'Assigned'
        Get-UnjudgedText $Result | Should -BeExactly ''
    }

    It 'keeps the policy of a role with an eligibility exactly at the scope' {
        $Result = Invoke-TestSelect `
            -Policy @(New-TestPolicy -Name 'Eligible' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000e') `
            -Eligibility @(New-TestFact -Scope $script:SelSub -RoleDefinitionId "$script:SelSubRoleDef/aaaaaaaa-0000-0000-0000-00000000000e")
        Get-KeptName $Result | Should -BeExactly 'Eligible'
        Get-UnjudgedText $Result | Should -BeExactly ''
    }

    It 'keeps a changed policy of a role nobody uses' {
        $Result = Invoke-TestSelect -Policy @(New-TestPolicy -Name 'Changed' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000c' -Modified $true)
        Get-KeptName $Result | Should -BeExactly 'Changed'
        Get-UnjudgedText $Result | Should -BeExactly ''
    }

    It 'omits an untouched policy of a role nobody uses at the scope' {
        $Result = Invoke-TestSelect `
            -Policy @(
                New-TestPolicy -Name 'Untouched' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000f'
                New-TestPolicy -Name 'Assigned' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000a'
            ) `
            -Assignment @(New-TestFact -Scope $script:SelSub -RoleDefinitionId "$script:SelSubRoleDef/aaaaaaaa-0000-0000-0000-00000000000a")
        # Reached: the selection ran and kept the used one beside it.
        Get-KeptName $Result | Should -BeExactly 'Assigned'
        Get-UnjudgedText $Result | Should -BeExactly ''
    }

    It 'does not keep a policy for an assignment or an eligibility of its role at another scope' {
        # A resource group below the subscription and the management group above it: both name the
        # role, neither stands exactly at the subscription policy's scope. A policy of the same role
        # at the management group IS kept, so the facts were read and matched there.
        $Guid = 'aaaaaaaa-0000-0000-0000-00000000000d'
        $Result = Invoke-TestSelect `
            -Policy @(
                New-TestPolicy -Name 'AtSubscription' -Scope $script:SelSub -RoleGuid $Guid
                New-TestPolicy -Name 'AtManagementGroup' -Scope $script:SelMg -RoleGuid $Guid
                New-TestPolicy -Name 'AtOtherSubscription' -Scope $script:SelOtherSub -RoleGuid $Guid
            ) `
            -Assignment @(
                New-TestFact -Scope $script:SelRg -RoleDefinitionId "$script:SelSubRoleDef/$Guid"
                New-TestFact -Scope $script:SelMg -RoleDefinitionId "$script:SelTenantRoleDef/$Guid"
            ) `
            -Eligibility @(
                New-TestFact -Scope $script:SelRg -RoleDefinitionId "$script:SelSubRoleDef/$Guid"
            )
        Get-KeptName $Result | Should -BeExactly 'AtManagementGroup'
        Get-UnjudgedText $Result | Should -BeExactly ''
        # And by an eligibility alone at the management group, with the assignment gone.
        $Result = Invoke-TestSelect `
            -Policy @(
                New-TestPolicy -Name 'AtSubscription' -Scope $script:SelSub -RoleGuid $Guid
                New-TestPolicy -Name 'AtManagementGroup' -Scope $script:SelMg -RoleGuid $Guid
            ) `
            -Eligibility @(
                New-TestFact -Scope $script:SelRg -RoleDefinitionId "$script:SelSubRoleDef/$Guid"
                New-TestFact -Scope $script:SelMg -RoleDefinitionId "$script:SelTenantRoleDef/$Guid"
            )
        Get-KeptName $Result | Should -BeExactly 'AtManagementGroup'
    }

    It 'matches the role on its guid across a subscription-scoped and a tenant-scoped role definition id, in any letter case' {
        $Result = Invoke-TestSelect `
            -Policy @(
                New-TestPolicy -Name 'ByAssignment' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000a'
                New-TestPolicy -Name 'ByEligibility' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000e' -RoleDefinitionId "$script:SelTenantRoleDef/aaaaaaaa-0000-0000-0000-00000000000e"
            ) `
            -Assignment @(New-TestFact -Scope $script:SelSub -RoleDefinitionId "$script:SelTenantRoleDef/AAAAAAAA-0000-0000-0000-00000000000A") `
            -Eligibility @(New-TestFact -Scope $script:SelSub -RoleDefinitionId "$script:SelSubRoleDef/aaaaaaaa-0000-0000-0000-00000000000e")
        Get-KeptName $Result | Should -BeExactly 'ByAssignment,ByEligibility'
        Get-UnjudgedText $Result | Should -BeExactly ''
    }

    It 'matches the scope in its canonical form: letter case and a trailing slash do not matter' {
        $Result = Invoke-TestSelect `
            -Policy @(
                New-TestPolicy -Name 'ByAssignment' -Scope "$script:SelSub/" -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000a'
                New-TestPolicy -Name 'ByEligibility' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000e'
            ) `
            -Assignment @(New-TestFact -Scope $script:SelSub.ToUpperInvariant() -RoleDefinitionId "$script:SelSubRoleDef/aaaaaaaa-0000-0000-0000-00000000000a") `
            -Eligibility @(New-TestFact -Scope "$($script:SelSub.ToUpperInvariant())/" -RoleDefinitionId "$script:SelSubRoleDef/aaaaaaaa-0000-0000-0000-00000000000e")
        Get-KeptName $Result | Should -BeExactly 'ByAssignment,ByEligibility'
        Get-UnjudgedText $Result | Should -BeExactly ''
    }

    It 'keeps every untouched unused policy at an unread scope and names that scope once' {
        $Result = Invoke-TestSelect `
            -Policy @(
                New-TestPolicy -Name 'UnreadOne' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-000000000001'
                New-TestPolicy -Name 'ReadUntouched' -Scope $script:SelOtherSub -RoleGuid 'aaaaaaaa-0000-0000-0000-000000000001'
                New-TestPolicy -Name 'UnreadTwo' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-000000000002'
            ) `
            -UnreadScope @("$($script:SelSub.ToUpperInvariant())/")
        Get-KeptName $Result | Should -BeExactly 'UnreadOne,UnreadTwo'
        Get-UnjudgedText $Result | Should -BeExactly $script:SelSub
    }

    It 'keeps a policy whose change cannot be judged (Modified $null) and names its scope' {
        $Result = Invoke-TestSelect -Policy @(New-TestPolicy -Name 'NoMetadata' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-000000000001' -Modified $null)
        Get-KeptName $Result | Should -BeExactly 'NoMetadata'
        Get-UnjudgedText $Result | Should -BeExactly $script:SelSub
    }

    It 'keeps a policy with an empty role definition id and names its scope, also beside an assignment with an empty role definition id' {
        # An assignment or eligibility with an empty role definition id is ignored, so it cannot stand
        # in for the policy's own missing role: the policy is kept as unjudged, never as used.
        $Result = Invoke-TestSelect `
            -Policy @(New-TestPolicy -Name 'NoRole' -Scope $script:SelSub -RoleGuid '') `
            -Assignment @(New-TestFact -Scope $script:SelSub -RoleDefinitionId '') `
            -Eligibility @(New-TestFact -Scope $script:SelSub -RoleDefinitionId '')
        Get-KeptName $Result | Should -BeExactly 'NoRole'
        Get-UnjudgedText $Result | Should -BeExactly $script:SelSub
    }

    It 'keeps the input order of the policies and names each unjudged scope once, in the order first seen' {
        $Result = Invoke-TestSelect `
            -Policy @(
                New-TestPolicy -Name 'C1' -Scope $script:SelOtherSub -RoleGuid 'aaaaaaaa-0000-0000-0000-000000000003' -Modified $true
                New-TestPolicy -Name 'U1' -Scope $script:SelOtherSub -RoleGuid 'aaaaaaaa-0000-0000-0000-000000000004' -Modified $null
                New-TestPolicy -Name 'Omitted' -Scope $script:SelOtherSub -RoleGuid 'aaaaaaaa-0000-0000-0000-000000000005'
                New-TestPolicy -Name 'A1' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000a'
                New-TestPolicy -Name 'U2' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-000000000006' -Modified $null
                New-TestPolicy -Name 'U3' -Scope $script:SelOtherSub -RoleGuid ''
            ) `
            -Assignment @(New-TestFact -Scope $script:SelSub -RoleDefinitionId "$script:SelSubRoleDef/aaaaaaaa-0000-0000-0000-00000000000a")
        Get-KeptName $Result | Should -BeExactly 'C1,U1,A1,U2,U3'
        Get-UnjudgedText $Result | Should -BeExactly "$script:SelOtherSub,$script:SelSub"
    }

    It 'returns empty lists for no policies' {
        $Result = Invoke-TestSelect -Assignment @(New-TestFact -Scope $script:SelSub -RoleDefinitionId "$script:SelSubRoleDef/aaaaaaaa-0000-0000-0000-00000000000a") -UnreadScope @($script:SelSub)
        ($Result.PSObject.Properties.Name -join ',') | Should -BeExactly 'Kept,UnjudgedScopes'
        @($Result.Kept).Count | Should -Be 0
        @($Result.UnjudgedScopes).Count | Should -Be 0
    }

    It 'sends nothing and signs in to nothing' {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth {}
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {}
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {}
        $Result = Invoke-TestSelect -Policy @(New-TestPolicy -Name 'Untouched' -Scope $script:SelSub -RoleGuid 'aaaaaaaa-0000-0000-0000-00000000000f')
        # Reached: the selection ran and judged the policy.
        Get-KeptName $Result | Should -BeExactly ''
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }
}
