BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Remove-OERRoleAssignment' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'rejects an id that is not a role assignment resource id' {
        { Remove-OERRoleAssignment -Id '/subscriptions/abc' -Confirm:$false -ErrorAction Stop } |
            Should -Throw -ErrorId 'InvalidRoleAssignmentId,Remove-OERRoleAssignment'
    }

    It 'DELETEs the full id with the pinned api-version and warns' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{ principalId = 'p'; principalType = 'User'; roleDefinitionId = 'r'; scope = '/subscriptions/s' }
            }
        }
        $Warnings = @()
        Remove-OERRoleAssignment `
            -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' `
            -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Path -eq '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059?api-version=2022-04-01'
        }
    }

    It 'treats a 204 (null response) as RoleAssignmentNotFound' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $null }
        { Remove-OERRoleAssignment `
            -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' `
            -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop } |
            Should -Throw -ErrorId 'RoleAssignmentNotFound,Remove-OERRoleAssignment'
    }

    It 'returns the deleted object only with -PassThru' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{ principalId = 'p' }
            }
        }
        $Silent = Remove-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Confirm:$false -WarningAction SilentlyContinue
        $Silent | Should -BeNullOrEmpty
        $Out = Remove-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Confirm:$false -PassThru -WarningAction SilentlyContinue
        $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleAssignment'
    }

    It 'honors -WhatIf (no ARM call)' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        Remove-OERRoleAssignment `
            -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' `
            -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
    }

    It 'binds -Id from piped Get-OERRoleAssignment output and processes multiple items' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/x/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
        }
        $Items = @(
            [PSCustomObject]@{ RoleAssignmentId = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a1111111-0000-0000-0000-000000000001' }
            [PSCustomObject]@{ RoleAssignmentId = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a2222222-0000-0000-0000-000000000002' }
        )
        $Items | Remove-OERRoleAssignment -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'scrubs the bearer-hygiene record when the ARM DELETE fails' {
        # CLAUDE.md SECURITY rule 6. Drives the transport catch at
        # source/Public/Remove-OERRoleAssignment.ps1:63 -- the cmdlet's only catch.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Remove-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
    }
}

Describe 'Remove-OERRoleAssignment: the -Id must begin with a slash (BL-177, A9)' {
    # The id is the request path, so a value that begins with a host suffix, an at sign or a scheme
    # would address another host. Refused before ShouldProcess, nothing sent. The address-shaped
    # values are built by concatenation so no address-shaped literal stands in the file.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/x/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
        }
    }

    It 'refuses <Label> with InvalidRoleAssignmentId and sends no request' -ForEach @(
        @{ Label = 'a leading host suffix'; Value = '.contoso.invalid/providers/Microsoft.Authorization/roleAssignments/a' }
        @{ Label = 'a leading at sign'; Value = ('@' + 'contoso.invalid/providers/Microsoft.Authorization/roleAssignments/a') }
        @{ Label = 'a leading port and at sign'; Value = (':443' + '@' + 'contoso.invalid/providers/Microsoft.Authorization/roleAssignments/a') }
        @{ Label = 'a scheme and host'; Value = 'https://contoso.invalid/providers/Microsoft.Authorization/roleAssignments/a' }
        @{ Label = 'no leading slash'; Value = 'providers/Microsoft.Authorization/roleAssignments/a' }
        @{ Label = 'a trailing line feed'; Value = "/subscriptions/aaaa1111-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleAssignments/a`n" }
        @{ Label = 'a trailing carriage return and line feed'; Value = "/subscriptions/aaaa1111-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleAssignments/a`r`n" }
        @{ Label = 'a line feed inside the last segment'; Value = "/subscriptions/aaaa1111-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleAssignments/a`nb" }
    ) {
        $Err = $null
        Remove-OERRoleAssignment -Id $Value -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Remove-OERRoleAssignment' })
        $Own.Count | Should -Be 1
        ([string]$Own[0].FullyQualifiedErrorId -split ',')[0] | Should -BeExactly 'InvalidRoleAssignmentId'
        $Own[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
    }

    It 'sends one request for a root scope id and for a subscription id (positive control)' {
        Remove-OERRoleAssignment -Id '/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Path -eq '/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059?api-version=2022-04-01'
        }
        Remove-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Path -eq '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059?api-version=2022-04-01'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 2 -Exactly
    }

    It 'passes the id the module issues at <Label> scope, piped from ConvertTo-OERRoleAssignment' -ForEach @(
        @{ Label = 'subscription'; Id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' }
        @{ Label = 'resource group'; Id = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' }
        @{ Label = 'management group'; Id = '/providers/Microsoft.Management/managementGroups/mg1/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' }
        @{ Label = 'resource'; Id = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sa/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' }
        @{ Label = 'root'; Id = '/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' }
    ) {
        $Piped = InModuleScope Omnicit.EntraRBAC -Parameters @{ RaId = $Id } {
            ConvertTo-OERRoleAssignment -InputObject ([PSCustomObject]@{ id = $RaId; name = 'n'; properties = [PSCustomObject]@{ scope = '/' } })
        }
        $Err = $null
        $Piped | Remove-OERRoleAssignment -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InvalidRoleAssignmentId*' }).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*?api-version=2022-04-01' }
    }
}

Describe 'Remove-OERRoleAssignment: an id that names another host sends nothing, outside any try (BL-177, A9)' {
    BeforeAll {
        . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
    }

    It 'sends no request and writes one InvalidRoleAssignmentId record' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $Text = @'
Import-Module Omnicit.EntraRBAC
$global:OERRaGuardArmCalls = 0
& (Get-Module Omnicit.EntraRBAC) {
    function script:Initialize-OERAuth {
        [CmdletBinding()]
        param($TenantId, [switch]$IncludeARM)
        # OER-GUARD-AUTH-STUB
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param($Method, $Path, $Body, [switch]$All)
        # OER-GUARD-ARM-STUB
        $global:OERRaGuardArmCalls++
        if ($global:OERRaGuardArmCalls -gt 5) { exit }
        $null
    }
}
$StubsInPlace = & (Get-Module Omnicit.EntraRBAC) {
    (Get-Command -Name Initialize-OERAuth -CommandType Function).ScriptBlock.ToString().Contains('OER-GUARD-AUTH-STUB') -and
    (Get-Command -Name Invoke-OERArmRequest -CommandType Function).ScriptBlock.ToString().Contains('OER-GUARD-ARM-STUB')
}
$Error.Clear()
$Output = @(Remove-OERRoleAssignment -Id '.contoso.invalid/providers/Microsoft.Authorization/roleAssignments/a' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable OerProbeErrors)
$Own = @($OerProbeErrors | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Remove-OERRoleAssignment' })
$ArmCalls1 = $global:OERRaGuardArmCalls
$global:OERRaGuardArmCalls = 0
$Error.Clear()
$Output2 = @(Remove-OERRoleAssignment -Id "/subscriptions/aaaa1111-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleAssignments/a`n" -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable OerProbeErrors2)
$Own2 = @($OerProbeErrors2 | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Remove-OERRoleAssignment' })
'STUBS IN PLACE: {0}' -f $StubsInPlace
'OUTPUT COUNT: {0}' -f $Output.Count
'ARM CALLS: {0}' -f $ArmCalls1
'OWN RECORDS: {0}' -f $Own.Count
foreach ($Record in $Own) { 'OWN ID: {0}' -f ([string]$Record.FullyQualifiedErrorId -split ',')[0] }
'LF OUTPUT COUNT: {0}' -f $Output2.Count
'LF ARM CALLS: {0}' -f $global:OERRaGuardArmCalls
'LF OWN RECORDS: {0}' -f $Own2.Count
foreach ($Record in $Own2) { 'LF OWN ID: {0}' -f ([string]$Record.FullyQualifiedErrorId -split ',')[0] }
'END OF SCRIPT REACHED'
'@
        $R = Invoke-OERWithConfirmAnswer -Answer '&No' -Script ([scriptblock]::Create($Text))

        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'STUBS IN PLACE: True'
        $R.Output | Should -Contain 'ARM CALLS: 0'
        $R.Output | Should -Contain 'OUTPUT COUNT: 0'
        $R.Output | Should -Contain 'OWN RECORDS: 1'
        $R.Output | Should -Contain 'OWN ID: InvalidRoleAssignmentId'
        $R.Output | Should -Contain 'LF OUTPUT COUNT: 0'
        $R.Output | Should -Contain 'LF ARM CALLS: 0'
        $R.Output | Should -Contain 'LF OWN RECORDS: 1'
        $R.Output | Should -Contain 'LF OWN ID: InvalidRoleAssignmentId'
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }
}
