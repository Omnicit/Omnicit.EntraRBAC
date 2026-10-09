BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERManagementGroup' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'authenticates with -IncludeARM' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        Get-OERManagementGroup
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -ParameterFilter { $IncludeARM }
    }

    It 'lists all management groups with paging' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG One' } }
            ) }
        }
        # mg1 is not the root, so its parent is read from Entities - List.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Path -like '*/getEntities?*' } {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ name = 'mg1'; type = 'Microsoft.Management/managementGroups'; properties = [PSCustomObject]@{ parent = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/t' }; parentDisplayNameChain = @('Tenant Root Group') } }
            ) }
        }
        $Result = Get-OERManagementGroup -ErrorAction Stop
        $Result.Name | Should -Be 'mg1'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ManagementGroup'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All
        }
    }

    It 'gets a single management group by name' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG One' } }
        }
        $Result = Get-OERManagementGroup -Name 'mg1'
        $Result.DisplayName | Should -Be 'MG One'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01'
        }
    }

    It 'adds $expand=children for -Expand and $recurse=true (with expand) for -Recurse' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG One' } }
        }
        $null = Get-OERManagementGroup -Name 'mg1' -Expand
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01&$expand=children'
        }
        $null = Get-OERManagementGroup -Name 'mg1' -Recurse
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01&$expand=children&$recurse=true'
        }
    }

    It 'writes a non-terminating error when the ARM call fails' {
        $ArmErr = InModuleScope Omnicit.EntraRBAC {
            Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' })
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw $ArmErr }
        { Get-OERManagementGroup -ErrorAction Stop } | Should -Throw -ErrorId 'AuthorizationFailed,Get-OERManagementGroup'
        { Get-OERManagementGroup -ErrorAction SilentlyContinue } | Should -Not -Throw
    }

    It 'returns a clean ManagementGroupNotFound for a name that does not exist (ARM 403 AuthorizationFailed)' {
        $AuthErr = InModuleScope Omnicit.EntraRBAC {
            Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"...does not have authorization... or the scope is invalid."}}' })
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw $AuthErr }.GetNewClosure()
        { Get-OERManagementGroup -Name 'Does not exist' -ErrorAction Stop } |
            Should -Throw -ErrorId 'ManagementGroupNotFound,Get-OERManagementGroup' `
                -ExpectedMessage "*'Does not exist' was not found, or you do not have access to it*"
    }

    It 'still surfaces a non-not-found ARM error (e.g. throttling) on the -Name path' {
        $ThrottleErr = InModuleScope Omnicit.EntraRBAC {
            Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests","message":"slow down"}}' })
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw $ThrottleErr }.GetNewClosure()
        { Get-OERManagementGroup -Name 'mg1' -ErrorAction Stop } |
            Should -Throw -ErrorId 'TooManyRequests,Get-OERManagementGroup'
    }

    Context 'scope-target naming (audit PR6)' {
        It 'accepts -ManagementGroup as an alias for -Name' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform'; name = 'mg-platform'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'Platform' } }
            }
            Get-OERManagementGroup -ManagementGroup 'mg-platform' | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Path -like '*managementGroups/mg-platform*'
            }
            # A real invocation alone would still pass via PowerShell's unambiguous prefix-name
            # matching against the pre-existing ManagementGroupName alias, even without a dedicated
            # -ManagementGroup alias. Assert the alias is actually declared so this stays locked in
            # even if a future parameter (e.g. -ManagementGroupId) makes the prefix match ambiguous.
            (Get-Command Get-OERManagementGroup).Parameters['Name'].Aliases | Should -Contain 'ManagementGroup'
        }

        It 'emits ResourceId and no bare Id, so an ARM path cannot mis-bind downstream id parameters' {
            # B-subscription-mg-id-collides: a bare Id holding the ARM path used to bind
            # -RoleEligibilityScheduleId and -PolicyId, both of which carry Alias('Id') plus
            # ValueFromPipelineByPropertyName.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG One' } }
            }
            $Mg = Get-OERManagementGroup -Name 'mg1'
            $Mg.PSObject.Properties.Name | Should -Contain 'ResourceId'
            $Mg.PSObject.Properties.Name | Should -Not -Contain 'Id'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM transport fails' {
        # CLAUDE.md SECURITY rule 6: the failed Invoke-WebRequest inside Invoke-OERArmRequest carries
        # Authorization: Bearer <token> on the request object recorded in $Error, so the catch must
        # call Remove-OERErrorRecord. Mock + Should -Invoke is the proof that holds for every rethrow
        # shape; a $global:Error + ReferenceEquals check is inert against a bare throw. This drives
        # the management group LIST catch (no -Name).
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Get-OERManagementGroup -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }

    # The Management Groups - List answer carries no parent. The parents come from ONE Entities -
    # List call per list; a parent that could not be read is reported, never shown as empty.
    Context 'the parent of every listed group (A10)' {
        BeforeAll {
            # Four groups on three levels: the tenant root t (its name equals its tenant id), mg-a
            # under the root, mg-b under mg-a and mg-c under mg-b.
            $MgList = [PSCustomObject]@{ value = @(
                    foreach ($Pair in @(@('t', 'Tenant Root Group'), @('mg-a', 'MG A'), @('mg-b', 'MG B'), @('mg-c', 'MG C'))) {
                        [PSCustomObject]@{
                            id         = "/providers/Microsoft.Management/managementGroups/$($Pair[0])"
                            name       = $Pair[0]
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{ tenantId = 't'; displayName = $Pair[1] }
                        }
                    }
                ) }
            $RootEntity = [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/t'
                name       = 't'
                type       = 'Microsoft.Management/managementGroups'
                properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'Tenant Root Group'; parent = $null }
            }
            $EntityA = [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg-a'
                name       = 'mg-a'
                type       = 'Microsoft.Management/managementGroups'
                properties = [PSCustomObject]@{
                    tenantId               = 't'
                    displayName            = 'MG A'
                    parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/t' }
                    parentNameChain        = @('t')
                    parentDisplayNameChain = @('Tenant Root Group')
                }
            }
            $EntityB = [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg-b'
                name       = 'mg-b'
                type       = 'Microsoft.Management/managementGroups'
                properties = [PSCustomObject]@{
                    tenantId               = 't'
                    displayName            = 'MG B'
                    parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                    parentNameChain        = @('t', 'mg-a')
                    parentDisplayNameChain = @('Tenant Root Group', 'MG A')
                }
            }
            $EntityC = [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg-c'
                name       = 'mg-c'
                type       = 'Microsoft.Management/managementGroups'
                properties = [PSCustomObject]@{
                    tenantId               = 't'
                    displayName            = 'MG C'
                    parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-b' }
                    parentNameChain        = @('t', 'mg-a', 'mg-b')
                    parentDisplayNameChain = @('Tenant Root Group', 'MG A', 'MG B')
                }
            }
            $UnreadTail = 'Their ParentId, ParentName and ParentDisplayName are empty, which here does not mean that they have no parent.'
        }

        BeforeEach {
            # One FILTERED mock per path: any other ARM call throws (Pester 6.2), so a parent read
            # without POST or -All, or on another path, fails the test instead of passing silently.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '*/managementGroups?api-version=*'
            } { $MgList }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '*/getEntities?*' -and $Method -eq 'POST' -and $All
            } { [PSCustomObject]@{ value = @($RootEntity, $EntityA, $EntityB, $EntityC) } }
        }

        It 'fills the parent of every listed group from one Entities - List call, the root left without one and no error' {
            $Out = @(Get-OERManagementGroup -ErrorAction SilentlyContinue -ErrorVariable Err)

            @($Out.ManagementGroupName) | Should -Be @('t', 'mg-a', 'mg-b', 'mg-c')
            $Out[0].ParentId | Should -Be $null
            $Out[0].ParentName | Should -Be $null
            $Out[0].ParentDisplayName | Should -Be $null
            $Out[1].ParentId | Should -BeExactly '/providers/Microsoft.Management/managementGroups/t'
            $Out[1].ParentName | Should -BeExactly 't'
            $Out[1].ParentDisplayName | Should -BeExactly 'Tenant Root Group'
            $Out[2].ParentId | Should -BeExactly '/providers/Microsoft.Management/managementGroups/mg-a'
            $Out[2].ParentName | Should -BeExactly 'mg-a'
            $Out[2].ParentDisplayName | Should -BeExactly 'MG A'
            $Out[3].ParentId | Should -BeExactly '/providers/Microsoft.Management/managementGroups/mg-b'
            $Out[3].ParentName | Should -BeExactly 'mg-b'
            $Out[3].ParentDisplayName | Should -BeExactly 'MG B'
            foreach ($Mg in $Out) { $Mg.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.ManagementGroup' }
            @($Err).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 2 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/getEntities?api-version=2020-05-01&$view=GroupsOnly' -and
                $Method -ceq 'POST' -and $All
            }
        }

        It 'still emits every group when Entities - List fails, and writes ONE ManagementGroupParentReadFailed naming the non-root groups' {
            $ArmErr = InModuleScope Omnicit.EntraRBAC {
                Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' })
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '*/getEntities?*' -and $Method -eq 'POST' -and $All
            } { [CmdletBinding()] param($Path, $Method, $Body, [switch]$All) throw $ArmErr }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }

            $Out = @(Get-OERManagementGroup -ErrorAction SilentlyContinue -ErrorVariable Err)

            @($Out.ManagementGroupName) | Should -Be @('t', 'mg-a', 'mg-b', 'mg-c')
            foreach ($Mg in $Out) {
                $Mg.ParentId | Should -Be $null
                $Mg.ParentName | Should -Be $null
                $Mg.ParentDisplayName | Should -Be $null
            }
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERManagementGroup' })
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'ManagementGroupParentReadFailed,Get-OERManagementGroup'
            $Own[0].CategoryInfo.Category | Should -Be 'ReadError'
            $Own[0].TargetObject | Should -BeOfType ([string])
            ($Own[0].TargetObject -is [string[]]) | Should -BeTrue
            @($Own[0].TargetObject) | Should -Be @('mg-a', 'mg-b', 'mg-c')
            $Own[0].Exception.Message | Should -BeExactly ("Could not read the parent of 3 management group(s): 'mg-a', 'mg-b', 'mg-c' -- the entity listing failed: AuthorizationFailed: denied. $UnreadTail")
            [object]::ReferenceEquals($Own[0].Exception.InnerException, $ArmErr.Exception) | Should -BeTrue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.FullyQualifiedErrorId -like 'AuthorizationFailed*' -and $Record.Exception.Message -ceq 'AuthorizationFailed: denied'
            }
        }

        It 'names only the group the Entities - List answer lacks, with the returned-no-parent reason and no inner exception' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '*/getEntities?*' -and $Method -eq 'POST' -and $All
            } { [PSCustomObject]@{ value = @($RootEntity, $EntityA, $EntityB) } }

            $Out = @(Get-OERManagementGroup -ErrorAction SilentlyContinue -ErrorVariable Err)

            @($Out.ManagementGroupName) | Should -Be @('t', 'mg-a', 'mg-b', 'mg-c')
            $Out[1].ParentName | Should -BeExactly 't'
            $Out[2].ParentName | Should -BeExactly 'mg-a'
            $Out[3].ParentId | Should -Be $null
            $Out[3].ParentName | Should -Be $null
            $Out[3].ParentDisplayName | Should -Be $null
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'ManagementGroupParentReadFailed,Get-OERManagementGroup'
            @($Err[0].TargetObject) | Should -Be @('mg-c')
            $Err[0].Exception.Message | Should -BeExactly ("Could not read the parent of 1 management group(s): 'mg-c' -- the entity listing (Entities - List) returned no parent for them. $UnreadTail")
            $Err[0].Exception.InnerException | Should -Be $null
        }

        It 'never calls Entities - List when only the tenant root group is listed' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '*/managementGroups?api-version=*'
            } { [PSCustomObject]@{ value = @($MgList.value[0]) } }

            $Out = @(Get-OERManagementGroup -ErrorAction SilentlyContinue -ErrorVariable Err)

            @($Out.ManagementGroupName) | Should -Be @('t')
            $Out[0].ParentId | Should -Be $null
            @($Err).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/getEntities?*' }
        }

        It 'recognises the root whose name differs from its tenant id only in case' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '*/managementGroups?api-version=*'
            } {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            id         = '/providers/Microsoft.Management/managementGroups/AAAAAAAA-0000-0000-0000-000000000001'
                            name       = 'AAAAAAAA-0000-0000-0000-000000000001'
                            properties = [PSCustomObject]@{ tenantId = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'Tenant Root Group' }
                        }
                    ) }
            }

            $Out = @(Get-OERManagementGroup -ErrorAction SilentlyContinue -ErrorVariable Err)

            $Out.Count | Should -Be 1
            $Out[0].ParentId | Should -Be $null
            @($Err).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/getEntities?*' }
        }

        It 'never takes an item without a name for the root, so its missing parent is reported' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '*/managementGroups?api-version=*'
            } {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/x'; properties = [PSCustomObject]@{ displayName = 'No name' } }
                    ) }
            }

            $Out = @(Get-OERManagementGroup -ErrorAction SilentlyContinue -ErrorVariable Err)

            $Out.Count | Should -Be 1
            $Out[0].ParentId | Should -Be $null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*/getEntities?*' }
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'ManagementGroupParentReadFailed,Get-OERManagementGroup'
            @($Err[0].TargetObject) | Should -Be @('')
        }

        It 'puts every group on the pipeline before the terminating ManagementGroupParentReadFailed under -ErrorAction Stop' {
            $ArmErr = InModuleScope Omnicit.EntraRBAC {
                Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' })
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '*/getEntities?*' -and $Method -eq 'POST' -and $All
            } { [CmdletBinding()] param($Path, $Method, $Body, [switch]$All) throw $ArmErr }

            $Seen = [System.Collections.Generic.List[object]]::new()
            $Caught = $null
            try {
                Get-OERManagementGroup -ErrorAction Stop | ForEach-Object { $Seen.Add($_) }
            } catch {
                $Caught = $PSItem
            }

            @($Seen.ManagementGroupName) | Should -Be @('t', 'mg-a', 'mg-b', 'mg-c')
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ManagementGroupParentReadFailed,Get-OERManagementGroup'
        }

        It 'reads details.parent for -Name and never calls Entities - List' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '*/managementGroups/mg-b?api-version=*'
            } {
                [PSCustomObject]@{
                    id         = '/providers/Microsoft.Management/managementGroups/mg-b'
                    name       = 'mg-b'
                    properties = [PSCustomObject]@{
                        tenantId    = 't'
                        displayName = 'MG B'
                        details     = [PSCustomObject]@{ parent = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a'; name = 'mg-a'; displayName = 'MG A' } }
                    }
                }
            }

            $Out = @(Get-OERManagementGroup -Name 'mg-b' -ErrorAction SilentlyContinue -ErrorVariable Err)

            $Out.Count | Should -Be 1
            $Out[0].ParentId | Should -BeExactly '/providers/Microsoft.Management/managementGroups/mg-a'
            $Out[0].ParentName | Should -BeExactly 'mg-a'
            $Out[0].ParentDisplayName | Should -BeExactly 'MG A'
            @($Err).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/getEntities?*' }
        }
    }

    # -Expand and -Recurse only mean something beside -Name, so they sit in the ByName parameter set
    # with it, and a call without -Name is refused at BINDING, before the begin block signs in.
    # Putting parameters into sets drops PowerShell's automatic positions, so -Name and -TenantId
    # declare theirs (0 and 1): 'Get-OERManagementGroup mg1 contoso.onmicrosoft.com' binds as before.
    Context 'parameter sets (A10)' {
        BeforeAll {
            # The cmdlet's own body, defined in a fresh host-less runspace further down.
            $Definition = (Get-Command -Module Omnicit.EntraRBAC -Name Get-OERManagementGroup).Definition

            # Runs one call of the cmdlet's body in a FRESH runspace with no host. There a missing
            # mandatory parameter is an error record, never a prompt, so the refusal can be observed.
            # Module auto-loading is off first, so a call that does bind cannot load the module and
            # reach its transport: Initialize-OERAuth is a stub that only records that begin ran.
            function Invoke-HostlessManagementGroup {
                param([string]$Body, [string]$Arguments)
                $Text = @(
                    '$PSModuleAutoLoadingPreference = ''None'''
                    'function Initialize-OERAuth { $global:OERBegan = $true }'
                    'function Get-OERManagementGroup {'
                    $Body
                    '}'
                    "Get-OERManagementGroup $Arguments"
                ) -join "`n"
                $Runspace = [runspacefactory]::CreateRunspace()
                $Runspace.Open()
                $Ps = [powershell]::Create()
                try {
                    $Ps.Runspace = $Runspace
                    $null = $Ps.AddScript($Text)
                    $Output = @()
                    $Thrown = $null
                    try { $Output = @($Ps.Invoke()) } catch { $Thrown = $PSItem }
                    $Records = [System.Collections.Generic.List[System.Management.Automation.ErrorRecord]]::new()
                    foreach ($Record in $Ps.Streams.Error) { $Records.Add($Record) }
                    if ($Thrown) {
                        # A terminating binding error surfaces as a MethodInvocationException from
                        # Invoke(); the record is on its InnerException.
                        $Cause = $Thrown.Exception
                        if ($Cause -is [System.Management.Automation.MethodInvocationException] -and $Cause.InnerException) {
                            $Cause = $Cause.InnerException
                        }
                        $Found = if ($Cause -is [System.Management.Automation.IContainsErrorRecord]) {
                            $Cause.ErrorRecord
                        } else {
                            [System.Management.Automation.ErrorRecord]::new($Cause, 'UnreadableInvokeFailure', 'NotSpecified', $null)
                        }
                        $Seen = @($Records | Where-Object { [object]::ReferenceEquals($_.Exception, $Found.Exception) })
                        if ($Seen.Count -eq 0) { $Records.Add($Found) }
                    }
                    [PSCustomObject]@{
                        Output = $Output
                        Errors = $Records.ToArray()
                        Began  = [bool]$Runspace.SessionStateProxy.PSVariable.GetValue('OERBegan')
                    }
                } finally {
                    $Ps.Dispose()
                    $Runspace.Dispose()
                }
            }
        }

        BeforeEach {
            # One FILTERED mock: a -Name read of any group. Any other ARM call throws (Pester 6.2), so
            # an unwanted list or parent read fails the test instead of passing silently.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter {
                $Path -like '/providers/Microsoft.Management/managementGroups/*?api-version=2020-05-01*'
            } {
                $Leaf = (($Path -split '\?')[0] -split '/')[-1]
                [PSCustomObject]@{
                    id         = "/providers/Microsoft.Management/managementGroups/$Leaf"
                    name       = $Leaf
                    properties = [PSCustomObject]@{ tenantId = 't'; displayName = "MG $Leaf" }
                }
            }
        }

        It 'declares List as the default set and keeps -Expand and -Recurse out of it' {
            $Command = Get-Command Get-OERManagementGroup
            $Binding = @($Command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] })
            $Binding.Count | Should -Be 1
            $Binding[0].DefaultParameterSetName | Should -BeExactly 'List'
            @($Command.ParameterSets.Name | Sort-Object) | Should -Be @('ByName', 'List')

            @($Command.Parameters['Expand'].ParameterSets.Keys) | Should -Be @('ByName')
            @($Command.Parameters['Recurse'].ParameterSets.Keys) | Should -Be @('ByName')
            $Command.Parameters['Expand'].ParameterSets['ByName'].IsMandatory | Should -BeFalse
            $Command.Parameters['Recurse'].ParameterSets['ByName'].IsMandatory | Should -BeFalse

            $ListSet = $Command.ParameterSets | Where-Object { $_.Name -eq 'List' }
            $ListSet.Parameters.Name | Should -Not -Contain 'Name'
            $ListSet.Parameters.Name | Should -Not -Contain 'Expand'
            $ListSet.Parameters.Name | Should -Not -Contain 'Recurse'
            $ListSet.Parameters.Name | Should -Contain 'TenantId'
            $ByNameSet = $Command.ParameterSets | Where-Object { $_.Name -eq 'ByName' }
            $ByNameSet.Parameters.Name | Should -Contain 'Name'
            $ByNameSet.Parameters.Name | Should -Contain 'Expand'
            $ByNameSet.Parameters.Name | Should -Contain 'Recurse'
            $ByNameSet.Parameters.Name | Should -Contain 'TenantId'
        }

        It 'makes -Name mandatory in ByName at position 0, still bound from the pipeline by property name' {
            $Name = (Get-Command Get-OERManagementGroup).Parameters['Name']
            @($Name.ParameterSets.Keys) | Should -Be @('ByName')
            $Name.ParameterSets['ByName'].IsMandatory | Should -BeTrue
            $Name.ParameterSets['ByName'].Position | Should -Be 0
            $Name.ParameterSets['ByName'].ValueFromPipelineByPropertyName | Should -BeTrue
            $Name.ParameterSets['ByName'].ValueFromPipeline | Should -BeFalse
            @($Name.Aliases) | Should -Be @('ManagementGroupName', 'ManagementGroup')
        }

        It 'gives -TenantId position 1 in every set and keeps it optional and non-empty' {
            $TenantId = (Get-Command Get-OERManagementGroup).Parameters['TenantId']
            @($TenantId.ParameterSets.Keys) | Should -Be @('__AllParameterSets')
            $TenantId.ParameterSets['__AllParameterSets'].Position | Should -Be 1
            $TenantId.ParameterSets['__AllParameterSets'].IsMandatory | Should -BeFalse
            @($TenantId.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }).Count | Should -Be 1
        }

        # Each of these used to be accepted and listed every group, the switch silently ignored. Run
        # in a fresh runspace with no host; never in this process, where an interactive host would
        # PROMPT for the missing -Name.
        $Refused = @(
            @{ Label = '-Recurse'; Arguments = '-Recurse' }
            @{ Label = '-Expand'; Arguments = '-Expand' }
            @{ Label = '-Expand -Recurse'; Arguments = '-Expand -Recurse' }
            @{ Label = '-TenantId with -Recurse'; Arguments = '-TenantId contoso.onmicrosoft.com -Recurse' }
        )
        It 'refuses <Label> without -Name at binding, before begin: no output and one MissingMandatoryParameter' -ForEach $Refused {
            $Result = Invoke-HostlessManagementGroup -Body $Definition -Arguments $Arguments

            @($Result.Output).Count | Should -Be 0
            @($Result.Errors).Count | Should -Be 1
            $Result.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'MissingMandatoryParameter,Get-OERManagementGroup'
            $Result.Began | Should -BeFalse -Because 'a refused binding must stop the command before its begin block signs in'
        }

        # The same harness must be able to SEE a call that binds, or the refusals above prove nothing.
        $Accepted = @(
            @{ Label = 'no parameters (the list)'; Arguments = '' }
            @{ Label = '-TenantId alone'; Arguments = '-TenantId contoso.onmicrosoft.com' }
            @{ Label = '-Name'; Arguments = '-Name mg1' }
            @{ Label = '-Name with -Expand and -Recurse'; Arguments = '-Name mg1 -Expand -Recurse' }
            @{ Label = 'the name and the tenant by position'; Arguments = 'mg1 contoso.onmicrosoft.com' }
        )
        It 'lets <Label> bind and reach the begin block (control for the refusals)' -ForEach $Accepted {
            $Result = Invoke-HostlessManagementGroup -Body $Definition -Arguments $Arguments

            $Result.Began | Should -BeTrue
            @($Result.Errors | Where-Object { $_.FullyQualifiedErrorId -like 'MissingMandatoryParameter*' }).Count | Should -Be 0
        }

        It 'refuses an empty -Name at binding and sends nothing' {
            { Get-OERManagementGroup -Name '' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationErrorEmptyStringNotAllowed,Get-OERManagementGroup'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        }

        It 'refuses a piped object with an empty ManagementGroupName and sends nothing' {
            { [PSCustomObject]@{ ManagementGroupName = '' } | Get-OERManagementGroup -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationErrorEmptyStringNotAllowed,Get-OERManagementGroup'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }

        It 'reads the group named by a piped ManagementGroupName' {
            $Out = @([PSCustomObject]@{ ManagementGroupName = 'mg1' } | Get-OERManagementGroup -ErrorAction Stop)

            $Out.Count | Should -Be 1
            $Out[0].ManagementGroupName | Should -BeExactly 'mg1'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01'
            }
        }

        It 'reads the group named by a piped ManagementGroup' {
            $Out = @([PSCustomObject]@{ ManagementGroup = 'mg2' } | Get-OERManagementGroup -ErrorAction Stop)

            $Out.Count | Should -Be 1
            $Out[0].ManagementGroupName | Should -BeExactly 'mg2'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/managementGroups/mg2?api-version=2020-05-01'
            }
        }

        It 'reads the group named by a piped Name' {
            $Out = @([PSCustomObject]@{ Name = 'mg3' } | Get-OERManagementGroup -ErrorAction Stop)

            $Out.Count | Should -Be 1
            $Out[0].ManagementGroupName | Should -BeExactly 'mg3'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/managementGroups/mg3?api-version=2020-05-01'
            }
        }

        It 'sends one read per piped object' {
            $Out = @(
                [PSCustomObject]@{ ManagementGroupName = 'mg1' }, [PSCustomObject]@{ ManagementGroupName = 'mg2' } |
                    Get-OERManagementGroup -ErrorAction Stop
            )

            @($Out.ManagementGroupName) | Should -Be @('mg1', 'mg2')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 2 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/managementGroups/mg2?api-version=2020-05-01'
            }
        }

        It 'sends the expand and recurse query for a converted group piped with -Recurse' {
            # The object a previous Get-OERManagementGroup emits: ManagementGroupName stored, Name an
            # AliasProperty of it from the module's type data.
            $Piped = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERManagementGroup -InputObject ([PSCustomObject]@{
                        id         = '/providers/Microsoft.Management/managementGroups/mg1'
                        name       = 'mg1'
                        properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG One' }
                    })
            }
            $Piped.Name | Should -BeExactly 'mg1'

            $Out = @($Piped | Get-OERManagementGroup -Recurse -ErrorAction Stop)

            $Out.Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01&$expand=children&$recurse=true'
            }
        }

        It 'binds the name by position' {
            $Out = @(Get-OERManagementGroup 'mg1' -ErrorAction Stop)

            $Out.Count | Should -Be 1
            $Out[0].ManagementGroupName | Should -BeExactly 'mg1'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter {
                $IncludeARM -and -not $TenantId
            }
        }

        It 'binds the name and the tenant by position' {
            $Out = @(Get-OERManagementGroup 'mg1' 'contoso.onmicrosoft.com' -ErrorAction Stop)

            $Out.Count | Should -Be 1
            $Out[0].ManagementGroupName | Should -BeExactly 'mg1'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter {
                $IncludeARM -and $TenantId -ceq 'contoso.onmicrosoft.com'
            }
        }
    }
}
