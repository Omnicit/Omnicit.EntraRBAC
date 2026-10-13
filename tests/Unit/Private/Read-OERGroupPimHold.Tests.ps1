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

# Read-OERGroupPimHold (BL-125, A3) is the apply engine's one read of whether PIM for Groups holds a
# group's members and owners or makes them eligible: the assignment read (Read-OERGroupPimAssignment)
# and the eligibility read (Read-OERGroupCollection -Collection PimEligibility, or the eligibility the
# caller already read), turned into a lookup by the rule's single owner, Get-OERGroupPimHeldAccess,
# which runs for real here. The two reads are mocked at the module boundary.
Describe 'Read-OERGroupPimHold' {
    BeforeAll {
        $script:AssignmentFailure = 'Could not read the PIM for Groups assignments of group g-1: Forbidden.'
        # The eligibility reader's message, as Read-OERGroupCollection words it, and the cause this
        # function gives for it: the closing sentence about the property Get-OERGroup omits is cut,
        # since it says nothing true in the apply engine's warning and row.
        $script:EligibilityMessage = 'Could not read PIM eligibility for group g-1: Forbidden. The PimEligibility property is omitted rather than reported as empty.'
        $script:EligibilityFailure = 'Could not read PIM eligibility for group g-1: Forbidden.'
    }

    Context 'both reads succeed' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
                $O = [PSCustomObject]@{
                    Read      = $true
                    Value     = @(
                        @{ principalId = 'u-act'; accessId = 'member'; assignmentType = 'activated'; endDateTime = '2026-10-13T12:00:00Z' }
                        @{ principalId = 'o-tb'; accessId = 'owner'; assignmentType = 'assigned'; endDateTime = '2026-12-31T00:00:00Z' }
                        @{ principalId = 'u-standing'; accessId = 'member'; assignmentType = 'assigned'; endDateTime = $null }
                    )
                    Message   = $null
                    Exception = $null
                }
                $O.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupPimAssignmentRead')
                $O
            }
            Mock -ModuleName $script:moduleName Read-OERGroupCollection {
                [PSCustomObject]@{
                    Collection = 'PimEligibility'
                    Read       = $true
                    Value      = @(@{ principalId = 'u-elig'; accessId = 'member' })
                    ErrorId    = $null
                    Message    = $null
                    Exception  = $null
                }
            }
        }

        It 'returns one GroupPimHold that is read, with the reason of every held principal keyed on principal and access type' {
            $W = $null
            $E = $null
            $Hold = @(InModuleScope $script:moduleName {
                    Read-OERGroupPimHold -GroupId 'g-1' -WarningVariable W -ErrorVariable E -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    if (@($W).Count -or @($E).Count) { throw 'Read-OERGroupPimHold wrote a warning or an error record.' }
                })
            $Hold.Count | Should -Be 1
            $Hold[0].PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.GroupPimHold'
            $Hold[0].Read | Should -BeTrue
            $Hold[0].Cause | Should -BeNullOrEmpty
            $Hold[0].Held | Should -BeOfType [hashtable]
            @($Hold[0].Held.Keys | Sort-Object) | Should -BeExactly @('o-tb|owner', 'u-act|member', 'u-elig|member')
            $Hold[0].Held['u-act|member'] | Should -BeExactly 'holds member access through an activation in PIM for Groups'
            $Hold[0].Held['o-tb|owner'] | Should -BeExactly 'holds owner access through a time-bound active assignment in PIM for Groups'
            $Hold[0].Held['u-elig|member'] | Should -BeExactly 'is eligible for member access in PIM for Groups'
            Should -Invoke -ModuleName $script:moduleName Read-OERGroupPimAssignment -Times 1 -Exactly -Scope It -ParameterFilter { $GroupId -eq 'g-1' }
            Should -Invoke -ModuleName $script:moduleName Read-OERGroupCollection -Times 1 -Exactly -Scope It -ParameterFilter { $GroupId -eq 'g-1' -and $Collection -eq 'PimEligibility' }
        }

        It 'adds nothing to Held for a standing membership' {
            $Hold = InModuleScope $script:moduleName { Read-OERGroupPimHold -GroupId 'g-1' }
            $Hold.Read | Should -BeTrue
            # Reached: the standing row was in the read, beside the held ones.
            $Hold.Held.Count | Should -Be 3
            $Hold.Held.ContainsKey('u-standing|member') | Should -BeFalse
            $Hold.Held.ContainsKey('u-standing|owner') | Should -BeFalse
        }

        It 'keys a principal id given in upper case in lower case' {
            Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
                [PSCustomObject]@{ Read = $true; Value = @(@{ principalId = 'U-UPPER'; accessId = 'Owner'; assignmentType = 'Activated' }); Message = $null; Exception = $null }
            }
            $Hold = InModuleScope $script:moduleName { Read-OERGroupPimHold -GroupId 'g-1' }
            @($Hold.Held.Keys | Sort-Object) | Should -BeExactly @('u-elig|member', 'u-upper|owner')
        }

        It 'with -EligibilityRead uses the eligibility it is given and makes no eligibility request' {
            $Hold = InModuleScope $script:moduleName {
                Read-OERGroupPimHold -GroupId 'g-1' -Eligibility @(@{ principalId = 'o-given'; accessId = 'owner' }) -EligibilityRead
            }
            Should -Invoke -ModuleName $script:moduleName Read-OERGroupCollection -Times 0 -Scope It
            Should -Invoke -ModuleName $script:moduleName Read-OERGroupPimAssignment -Times 1 -Exactly -Scope It -ParameterFilter { $GroupId -eq 'g-1' }
            $Hold.Read | Should -BeTrue
            $Hold.Cause | Should -BeNullOrEmpty
            @($Hold.Held.Keys | Sort-Object) | Should -BeExactly @('o-given|owner', 'o-tb|owner', 'u-act|member')
            $Hold.Held['o-given|owner'] | Should -BeExactly 'is eligible for owner access in PIM for Groups'
        }

        It 'with -EligibilityRead and no eligibility (empty, or null) holds only what the assignment read holds' {
            $FromEmpty = InModuleScope $script:moduleName { Read-OERGroupPimHold -GroupId 'g-1' -Eligibility @() -EligibilityRead }
            $FromNull = InModuleScope $script:moduleName { Read-OERGroupPimHold -GroupId 'g-1' -Eligibility $null -EligibilityRead }
            foreach ($Hold in $FromEmpty, $FromNull) {
                $Hold.Read | Should -BeTrue
                @($Hold.Held.Keys | Sort-Object) | Should -BeExactly @('o-tb|owner', 'u-act|member')
            }
            Should -Invoke -ModuleName $script:moduleName Read-OERGroupCollection -Times 0 -Scope It
            Should -Invoke -ModuleName $script:moduleName Read-OERGroupPimAssignment -Times 2 -Exactly -Scope It
        }
    }

    Context 'a read fails' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
                [PSCustomObject]@{ Read = $true; Value = @(@{ principalId = 'u-act'; accessId = 'member'; assignmentType = 'activated' }); Message = $null; Exception = $null }
            }
            Mock -ModuleName $script:moduleName Read-OERGroupCollection {
                [PSCustomObject]@{ Collection = 'PimEligibility'; Read = $true; Value = @(@{ principalId = 'u-elig'; accessId = 'member' }); ErrorId = $null; Message = $null; Exception = $null }
            }
        }

        It 'is not read when the assignment read fails, and the cause is that read''s message' {
            Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
                [PSCustomObject]@{ Read = $false; Value = $null; Message = 'Could not read the PIM for Groups assignments of group g-1: Forbidden.'; Exception = [System.Exception]::new('Forbidden') }
            }
            $W = $null
            $E = $null
            $Hold = InModuleScope $script:moduleName {
                $Out = Read-OERGroupPimHold -GroupId 'g-1' -WarningVariable W -ErrorVariable E -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if (@($W).Count -or @($E).Count) { throw 'Read-OERGroupPimHold wrote a warning or an error record.' }
                $Out
            }
            $Hold.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.GroupPimHold'
            $Hold.Read | Should -BeFalse
            $Hold.Cause | Should -BeExactly $script:AssignmentFailure
            $Hold.Held | Should -BeOfType [hashtable]
            $Hold.Held.Count | Should -Be 0
            # Reached: the eligibility was read all the same.
            Should -Invoke -ModuleName $script:moduleName Read-OERGroupCollection -Times 1 -Exactly -Scope It -ParameterFilter { $Collection -eq 'PimEligibility' }
        }

        It 'is not read when the eligibility read fails, and the cause is that read''s message without the omitted-property sentence' {
            Mock -ModuleName $script:moduleName Read-OERGroupCollection {
                [PSCustomObject]@{ Collection = 'PimEligibility'; Read = $false; Value = $null; ErrorId = 'GroupPimEligibilityReadFailed'
                    Message = $script:EligibilityMessage
                    Exception = [System.Exception]::new('Forbidden') }
            }
            $Hold = InModuleScope $script:moduleName { Read-OERGroupPimHold -GroupId 'g-1' }
            $Hold.Read | Should -BeFalse
            $Hold.Cause | Should -BeExactly $script:EligibilityFailure
            $Hold.Cause | Should -Not -Match 'property is omitted'
            $Hold.Held.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Read-OERGroupPimAssignment -Times 1 -Exactly -Scope It
        }

        It 'joins both messages with a semicolon, the assignment read first, when both reads fail' {
            Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
                [PSCustomObject]@{ Read = $false; Value = $null; Message = 'Could not read the PIM for Groups assignments of group g-1: Forbidden.'; Exception = [System.Exception]::new('Forbidden') }
            }
            Mock -ModuleName $script:moduleName Read-OERGroupCollection {
                [PSCustomObject]@{ Collection = 'PimEligibility'; Read = $false; Value = $null; ErrorId = 'GroupPimEligibilityReadFailed'
                    Message = $script:EligibilityMessage
                    Exception = [System.Exception]::new('Forbidden') }
            }
            $Hold = InModuleScope $script:moduleName { Read-OERGroupPimHold -GroupId 'g-1' }
            $Hold.Read | Should -BeFalse
            $Hold.Cause | Should -BeExactly ($script:AssignmentFailure + '; ' + $script:EligibilityFailure)
            $Hold.Held.Count | Should -Be 0
        }

        It 'keeps an eligibility message that does not end with the omitted-property sentence as it is' {
            Mock -ModuleName $script:moduleName Read-OERGroupCollection {
                [PSCustomObject]@{ Collection = 'PimEligibility'; Read = $false; Value = $null; ErrorId = 'GroupPimEligibilityReadFailed'
                    Message = 'Could not read PIM eligibility for group g-1: Forbidden.'; Exception = [System.Exception]::new('Forbidden') }
            }
            $Hold = InModuleScope $script:moduleName { Read-OERGroupPimHold -GroupId 'g-1' }
            $Hold.Read | Should -BeFalse
            $Hold.Cause | Should -BeExactly 'Could not read PIM eligibility for group g-1: Forbidden.'
        }

        It 'with -EligibilityRead is not read when the assignment read fails, naming only that read' {
            Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
                [PSCustomObject]@{ Read = $false; Value = $null; Message = 'Could not read the PIM for Groups assignments of group g-1: Forbidden.'; Exception = [System.Exception]::new('Forbidden') }
            }
            $Hold = InModuleScope $script:moduleName { Read-OERGroupPimHold -GroupId 'g-1' -Eligibility @(@{ principalId = 'u-elig'; accessId = 'member' }) -EligibilityRead }
            $Hold.Read | Should -BeFalse
            $Hold.Cause | Should -BeExactly $script:AssignmentFailure
            $Hold.Held.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Read-OERGroupCollection -Times 0 -Scope It
        }
    }

    Context 'the eligibility read fails in the real eligibility reader' {
        # Read-OERGroupCollection runs for real here, so a change to the words it closes its failure
        # with turns this red rather than letting the sentence back into the apply engine's cause.
        BeforeEach {
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
                [PSCustomObject]@{ Read = $true; Value = @(); Message = $null; Exception = $null }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw [System.Exception]::new('Insufficient privileges (403)') }
        }

        It 'cuts the omitted-property sentence from the reader''s own message and keeps the rest' {
            $Hold = InModuleScope $script:moduleName { Read-OERGroupPimHold -GroupId 'g-1' }
            # Reach proof: the reader sent the eligibility request.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Uri -like '*eligibilityScheduleInstances*' }
            $Hold.Read | Should -BeFalse
            $Hold.Cause | Should -BeExactly 'Could not read PIM eligibility for group g-1: Insufficient privileges (403).'
            $Hold.Cause | Should -Not -Match 'property is omitted'
        }
    }
}
