BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERGroupPimHeldAccess' {
    # BL-125 (A3), ruling R1: an assignment schedule instance holds its principal's access through PIM
    # unless it is a standing one (assignmentType 'assigned' and no endDateTime). Graph answers the
    # enum values in lower case (measured live 2026-10-13); the rule compares without regard to case.
    # Rows are hashtables, the shape Invoke-MgGraphRequest answers with.
    BeforeAll {
        # Runs the helper in module scope and hands every object back, so a test can count them.
        function Invoke-HeldAccess {
            param([object[]]$Assignment, [object[]]$Eligibility, [switch]$NoAssignment, [switch]$NoEligibility)
            $Arguments = @{ A = $Assignment; E = $Eligibility; NA = [bool]$NoAssignment; NE = [bool]$NoEligibility }
            InModuleScope Omnicit.EntraRBAC -Parameters $Arguments {
                param($A, $E, $NA, $NE)
                $Params = @{}
                if (-not $NA) { $Params.Assignment = $A }
                if (-not $NE) { $Params.Eligibility = $E }
                @(Get-OERGroupPimHeldAccess @Params)
            }
        }
    }

    Context 'the rule (R1)' {
        It 'returns nothing for a standing assignment: assigned and no end' {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; memberType = 'direct'; assignmentType = 'assigned'; startDateTime = $null; endDateTime = $null }
                ))
            $Held.Count | Should -Be 0
        }

        It 'returns nothing for a standing assignment whose type is spelled <Spelling>' -ForEach @(
            @{ Spelling = 'Assigned' }
            @{ Spelling = 'ASSIGNED' }
        ) {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = $Spelling; endDateTime = $null }
                ))
            $Held.Count | Should -Be 0
        }

        It 'returns nothing for a standing assignment whose end is an empty or blank text (<Label>)' -ForEach @(
            @{ Label = 'empty'; End = '' }
            @{ Label = 'blank'; End = '   ' }
        ) {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'assigned'; endDateTime = $End }
                ))
            $Held.Count | Should -Be 0
        }

        It 'reads an activation as Activated, whatever the case (<Spelling>)' -ForEach @(
            @{ Spelling = 'activated' }
            @{ Spelling = 'Activated' }
        ) {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = $Spelling; startDateTime = '2026-10-13T08:00:00Z'; endDateTime = $null }
                ))
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly 'Activated'
            $Held[0].AccessType | Should -BeExactly 'member'
            $Held[0].PrincipalId | Should -BeExactly 'u-1'
        }

        It 'reads an activation that carries an end as Activated, not TimeBound' {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'activated'; endDateTime = '2026-10-13T16:00:00Z' }
                ))
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly 'Activated'
        }

        It 'reads an assigned instance with an end given as text as TimeBound' {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'assigned'; endDateTime = '2026-12-31T00:00:00Z' }
                ))
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly 'TimeBound'
        }

        It 'reads an assigned instance with an end given as a DateTime object as TimeBound' {
            # The Graph SDK hands endDateTime back as a DateTime, not as text.
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'assigned'; endDateTime = [datetime]::new(2026, 12, 31, 0, 0, 0, [System.DateTimeKind]::Utc) }
                ))
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly 'TimeBound'
        }

        It 'reads an instance with no end and an assignment type of <Label> as Unrecognized' -ForEach @(
            @{ Label = 'unknownFutureValue'; Type = 'unknownFutureValue'; Missing = $false }
            @{ Label = 'an empty text'; Type = ''; Missing = $false }
            @{ Label = 'null'; Type = $null; Missing = $false }
            @{ Label = 'a missing key'; Type = $null; Missing = $true }
        ) {
            $Row = @{ principalId = 'u-1'; accessId = 'member'; endDateTime = $null }
            if (-not $Missing) { $Row.assignmentType = $Type }
            $Held = @(Invoke-HeldAccess -Assignment @($Row))
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly 'Unrecognized'
        }

        It 'reads an unknownFutureValue instance that carries an end as TimeBound' {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'unknownFutureValue'; endDateTime = '2026-12-31T00:00:00Z' }
                ))
            $Held[0].Kind | Should -BeExactly 'TimeBound'
        }

        It 'never consults memberType: a standing instance inherited through a group is still standing, an activation through a group still held' {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; memberType = 'group'; assignmentType = 'assigned'; endDateTime = $null }
                    @{ principalId = 'u-2'; accessId = 'member'; memberType = 'group'; assignmentType = 'activated'; endDateTime = $null }
                ))
            $Held.Count | Should -Be 1
            $Held[0].PrincipalId | Should -BeExactly 'u-2'
            $Held[0].Kind | Should -BeExactly 'Activated'
        }

        It 'reads a PSCustomObject row the same as a hashtable row' {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    [PSCustomObject]@{ principalId = 'u-1'; accessId = 'owner'; assignmentType = 'activated'; endDateTime = $null }
                    [PSCustomObject]@{ principalId = 'u-2'; accessId = 'owner'; assignmentType = 'assigned'; endDateTime = $null }
                ))
            $Held.Count | Should -Be 1
            $Held[0].PrincipalId | Should -BeExactly 'u-1'
            $Held[0].AccessType | Should -BeExactly 'owner'
        }
    }

    Context 'the access type' {
        It 'takes the access type from accessId (<Label>)' -ForEach @(
            @{ Label = 'owner'; Access = 'owner'; Missing = $false; Expected = 'owner' }
            @{ Label = 'member'; Access = 'member'; Missing = $false; Expected = 'member' }
            @{ Label = 'empty, read as member'; Access = ''; Missing = $false; Expected = 'member' }
            @{ Label = 'missing, read as member'; Access = $null; Missing = $true; Expected = 'member' }
        ) {
            $Row = @{ principalId = 'u-1'; assignmentType = 'activated'; endDateTime = $null }
            if (-not $Missing) { $Row.accessId = $Access }
            $Held = @(Invoke-HeldAccess -Assignment @($Row))
            $Held.Count | Should -Be 1
            $Held[0].AccessType | Should -BeExactly $Expected
        }

        It 'takes the access type of an eligibility from its accessId, member when it has none' {
            $Held = @(Invoke-HeldAccess -Eligibility @(
                    @{ principalId = 'u-1'; accessId = 'owner' }
                    @{ principalId = 'u-2' }
                ))
            $Held.Count | Should -Be 2
            $Held[0].AccessType | Should -BeExactly 'owner'
            $Held[1].AccessType | Should -BeExactly 'member'
        }
    }

    Context 'eligibility' {
        It 'reads every eligibility instance as Eligible, a standing-shaped one included' {
            $Held = @(Invoke-HeldAccess -Eligibility @(
                    @{ principalId = 'u-1'; accessId = 'member'; memberType = 'direct'; startDateTime = $null; endDateTime = $null }
                    @{ principalId = 'u-2'; accessId = 'member'; endDateTime = '2026-12-31T00:00:00Z' }
                ))
            $Held.Count | Should -Be 2
            @($Held | ForEach-Object { $_.Kind }) | Should -Be @('Eligible', 'Eligible')
            @($Held | ForEach-Object { $_.PrincipalId }) | Should -Be @('u-1', 'u-2')
        }
    }

    Context 'one object per principal and access (Review Focus 2)' {
        It 'returns exactly one object, owner and Activated, for a principal standing as member and activated as owner' {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'assigned'; endDateTime = $null }
                    @{ principalId = 'u-1'; accessId = 'owner'; assignmentType = 'activated'; endDateTime = $null }
                ))
            $Held.Count | Should -Be 1
            $Held[0].PrincipalId | Should -BeExactly 'u-1'
            $Held[0].AccessType | Should -BeExactly 'owner'
            $Held[0].Kind | Should -BeExactly 'Activated'
        }

        It 'returns one object, Activated, for a principal both eligible and activated for member access' {
            $Held = @(Invoke-HeldAccess `
                    -Assignment @(@{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'activated'; endDateTime = $null }) `
                    -Eligibility @(@{ principalId = 'u-1'; accessId = 'member' }))
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly 'Activated'
        }

        It 'lets an assignment kind win over Eligible whichever list names the principal first' {
            # The eligibility is given first in neither sense: it is a separate list, and an assignment
            # kind wins over Eligible for the same principal and access.
            $Held = @(Invoke-HeldAccess `
                    -Eligibility @(@{ principalId = 'u-1'; accessId = 'owner' }) `
                    -Assignment @(@{ principalId = 'U-1'; accessId = 'owner'; assignmentType = 'assigned'; endDateTime = '2026-12-31T00:00:00Z' }))
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly 'TimeBound'
        }

        It 'keeps the first assignment kind in input order when one principal has several' {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'assigned'; endDateTime = '2026-12-31T00:00:00Z' }
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'activated'; endDateTime = $null }
                ))
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly 'TimeBound'
        }

        It 'keeps member and owner apart for one principal' {
            $Held = @(Invoke-HeldAccess `
                    -Assignment @(@{ principalId = 'u-1'; accessId = 'owner'; assignmentType = 'activated'; endDateTime = $null }) `
                    -Eligibility @(@{ principalId = 'u-1'; accessId = 'member' }))
            $Held.Count | Should -Be 2
            @($Held | ForEach-Object { "$($_.AccessType)/$($_.Kind)" }) | Should -Be @('owner/Activated', 'member/Eligible')
        }
    }

    Context 'the principal id' {
        It 'returns the principal id in lower case' {
            $Held = @(Invoke-HeldAccess `
                    -Assignment @(@{ principalId = 'AAAA1111-0000-0000-0000-00000000BBBB'; accessId = 'member'; assignmentType = 'activated'; endDateTime = $null }) `
                    -Eligibility @(@{ principalId = 'CCCC2222-0000-0000-0000-00000000DDDD'; accessId = 'member' }))
            @($Held | ForEach-Object { $_.PrincipalId }) | Should -BeExactly @('aaaa1111-0000-0000-0000-00000000bbbb', 'cccc2222-0000-0000-0000-00000000dddd')
        }

        It 'treats two spellings of one principal id as one principal' {
            $Held = @(Invoke-HeldAccess -Assignment @(
                    @{ principalId = 'U-1'; accessId = 'member'; assignmentType = 'activated'; endDateTime = $null }
                    @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'assigned'; endDateTime = '2026-12-31T00:00:00Z' }
                ))
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly 'Activated'
        }

        It 'skips an instance with no principal id (<Label>)' -ForEach @(
            @{ Label = 'missing'; Missing = $true; Id = $null }
            @{ Label = 'null'; Missing = $false; Id = $null }
            @{ Label = 'empty'; Missing = $false; Id = '' }
        ) {
            $Row = @{ accessId = 'member'; assignmentType = 'activated'; endDateTime = $null }
            if (-not $Missing) { $Row.principalId = $Id }
            $Elig = @{ accessId = 'member' }
            if (-not $Missing) { $Elig.principalId = $Id }
            @(Invoke-HeldAccess -Assignment @($Row) -Eligibility @($Elig)).Count | Should -Be 0
        }
    }

    Context 'empty input' {
        It 'returns nothing for <Label>' -ForEach @(
            @{ Label = 'no parameter at all'; Splat = @{ NoAssignment = $true; NoEligibility = $true } }
            @{ Label = 'null lists'; Splat = @{ Assignment = $null; Eligibility = $null } }
            @{ Label = 'empty lists'; Splat = @{ Assignment = @(); Eligibility = @() } }
            @{ Label = 'lists holding a null'; Splat = @{ Assignment = @($null); Eligibility = @($null) } }
        ) {
            @(Invoke-HeldAccess @Splat).Count | Should -Be 0
        }

        It 'writes nothing but its objects to any stream' {
            $Stream = InModuleScope Omnicit.EntraRBAC {
                @(Get-OERGroupPimHeldAccess -Assignment @(
                        @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'activated'; endDateTime = $null }
                    ) -Eligibility @(@{ principalId = 'u-2' }) -Verbose *>&1)
            }
            $Stream.Count | Should -Be 2
            @($Stream | Where-Object { $_.PSObject.TypeNames[0] -ne 'Omnicit.EntraRBAC.GroupPimHeldAccess' }).Count | Should -Be 0
        }

        It 'makes no request' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { throw 'should not be called' }
                $null = Get-OERGroupPimHeldAccess -Assignment @(@{ principalId = 'u-1'; assignmentType = 'activated' })
                Should -Invoke Invoke-OERGraphRequest -Times 0
            }
        }
    }

    Context 'the output object' {
        It 'is tagged and carries PrincipalId, AccessType, Kind and Reason, in that order' {
            $Held = @(Invoke-HeldAccess -Assignment @(@{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'activated'; endDateTime = $null }))
            $Held[0].PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.GroupPimHeldAccess'
            @($Held[0].PSObject.Properties.Name) | Should -BeExactly @('PrincipalId', 'AccessType', 'Kind', 'Reason')
        }

        It 'words the reason of <Kind> for <Access> access exactly' -ForEach @(
            @{ Kind = 'Activated'; Access = 'member'; Type = 'activated'; End = $null; Elig = $false; Reason = 'holds member access through an activation in PIM for Groups' }
            @{ Kind = 'Activated'; Access = 'owner'; Type = 'activated'; End = $null; Elig = $false; Reason = 'holds owner access through an activation in PIM for Groups' }
            @{ Kind = 'TimeBound'; Access = 'member'; Type = 'assigned'; End = '2026-12-31T00:00:00Z'; Elig = $false; Reason = 'holds member access through a time-bound active assignment in PIM for Groups' }
            @{ Kind = 'TimeBound'; Access = 'owner'; Type = 'assigned'; End = '2026-12-31T00:00:00Z'; Elig = $false; Reason = 'holds owner access through a time-bound active assignment in PIM for Groups' }
            @{ Kind = 'Unrecognized'; Access = 'member'; Type = 'unknownFutureValue'; End = $null; Elig = $false; Reason = 'holds member access through a PIM for Groups active assignment that is not a standing one' }
            @{ Kind = 'Unrecognized'; Access = 'owner'; Type = 'unknownFutureValue'; End = $null; Elig = $false; Reason = 'holds owner access through a PIM for Groups active assignment that is not a standing one' }
            @{ Kind = 'Eligible'; Access = 'member'; Type = $null; End = $null; Elig = $true; Reason = 'is eligible for member access in PIM for Groups' }
            @{ Kind = 'Eligible'; Access = 'owner'; Type = $null; End = $null; Elig = $true; Reason = 'is eligible for owner access in PIM for Groups' }
        ) {
            $Held = if ($Elig) {
                @(Invoke-HeldAccess -Eligibility @(@{ principalId = 'u-1'; accessId = $Access }))
            } else {
                @(Invoke-HeldAccess -Assignment @(@{ principalId = 'u-1'; accessId = $Access; assignmentType = $Type; endDateTime = $End }))
            }
            $Held.Count | Should -Be 1
            $Held[0].Kind | Should -BeExactly $Kind
            $Held[0].AccessType | Should -BeExactly $Access
            $Held[0].Reason | Should -BeExactly $Reason
        }
    }
}
