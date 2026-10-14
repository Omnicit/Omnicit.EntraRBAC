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

Describe 'ConvertTo-OERGroup' {
    It 'maps a Graph group hashtable to a tagged object' {
        InModuleScope $script:moduleName {
            $Graph = @{
                id = 'gid-1'; displayName = 'role_sec_identity_administrator'
                description = 'Core identity admin'; mailNickname = 'role_sec_identity_administrator'
                securityEnabled = $true; isAssignableToRole = $true
                groupTypes = @(); membershipRule = $null
            }
            $Out = ConvertTo-OERGroup -InputObject $Graph
            $Out.Id | Should -Be 'gid-1'
            $Out.DisplayName | Should -Be 'role_sec_identity_administrator'
            $Out.IsAssignableToRole | Should -BeTrue
            $Out.GroupType | Should -Be 'RoleEnabled'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Group'
        }
    }

    It 'classifies a dynamic security group as Dynamic' {
        InModuleScope $script:moduleName {
            $Graph = @{ id = 'g2'; displayName = 'dyn'; securityEnabled = $true; isAssignableToRole = $false
                groupTypes = @('DynamicMembership'); membershipRule = '(user.department -eq "IT")' }
            (ConvertTo-OERGroup -InputObject $Graph).GroupType | Should -Be 'Dynamic'
        }
    }

    It 'classifies a plain security group as Regular' {
        InModuleScope $script:moduleName {
            $Graph = @{ id = 'g3'; displayName = 'reg'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            (ConvertTo-OERGroup -InputObject $Graph).GroupType | Should -Be 'Regular'
        }
    }

    It 'exposes MembershipRuleProcessingState on the converted group' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $G = ConvertTo-OERGroup -InputObject ([PSCustomObject]@{
                    id = 'g-1'; displayName = 'x'; groupTypes = @('DynamicMembership')
                    membershipRule = 'user.department -eq "A"'; membershipRuleProcessingState = 'Paused'
                })
            $G.MembershipRuleProcessingState | Should -BeExactly 'Paused'
        }
    }

    Context 'MailEnabled, Visibility and CreatedDateTime (the roster identity, BL-130)' {
        It 'reads a security group: mailEnabled false, no visibility, a created time' {
            InModuleScope Omnicit.EntraRBAC {
                $G = ConvertTo-OERGroup -InputObject @{
                    id = 'g-sec'; displayName = 'sec'; securityEnabled = $true; mailEnabled = $false
                    groupTypes = @(); visibility = $null; createdDateTime = '2026-01-02T03:04:05Z'
                }
                $G.MailEnabled | Should -BeOfType [bool]
                $G.MailEnabled | Should -BeFalse
                $G.Visibility | Should -BeNullOrEmpty
                $G.CreatedDateTime | Should -BeExactly '2026-01-02T03:04:05Z'
            }
        }

        It 'reads a Microsoft 365 group: mailEnabled true, Private, a created time' {
            InModuleScope Omnicit.EntraRBAC {
                $G = ConvertTo-OERGroup -InputObject @{
                    id = 'g-m365'; displayName = 'team'; securityEnabled = $false; mailEnabled = $true
                    groupTypes = @('Unified'); visibility = 'Private'; createdDateTime = '2026-02-03T04:05:06Z'
                }
                $G.MailEnabled | Should -BeOfType [bool]
                $G.MailEnabled | Should -BeTrue
                $G.SecurityEnabled | Should -BeFalse
                @($G.GroupTypes) | Should -Be @('Unified')
                $G.Visibility | Should -BeExactly 'Private'
                $G.CreatedDateTime | Should -BeExactly '2026-02-03T04:05:06Z'
            }
        }

        It 'reads all three as empty from an object that carries none of them' {
            InModuleScope Omnicit.EntraRBAC {
                $G = ConvertTo-OERGroup -InputObject ([PSCustomObject]@{ id = 'g-bare'; displayName = 'bare' })
                $Names = @($G.PSObject.Properties.Name)
                $Names | Should -Contain 'MailEnabled'
                $Names | Should -Contain 'Visibility'
                $Names | Should -Contain 'CreatedDateTime'
                $null -eq $G.MailEnabled | Should -BeTrue
                $null -eq $G.Visibility | Should -BeTrue
                $null -eq $G.CreatedDateTime | Should -BeTrue
            }
        }

        It 'reads mailEnabled as <Expected> from <Case>' -ForEach @(
            @{ Case = 'true'; Raw = $true; Expected = $true }
            @{ Case = 'false'; Raw = $false; Expected = $false }
            @{ Case = 'null'; Raw = $null; Expected = $null }
            @{ Case = 'the string true (not an answer)'; Raw = 'true'; Expected = $null }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Raw = $Raw; Expected = $Expected } {
                param($Raw, $Expected)
                $G = ConvertTo-OERGroup -InputObject @{ id = 'g-1'; displayName = 'a'; mailEnabled = $Raw }
                if ($null -eq $Expected) { $null -eq $G.MailEnabled | Should -BeTrue }
                else { $G.MailEnabled | Should -BeOfType [bool]; $G.MailEnabled | Should -Be $Expected }
            }
        }

        It 'reads visibility <Case> as <Expected>' -ForEach @(
            @{ Case = 'Public'; Raw = 'Public'; Expected = 'Public' }
            @{ Case = 'HiddenMembership'; Raw = 'HiddenMembership'; Expected = 'HiddenMembership' }
            @{ Case = 'null'; Raw = $null; Expected = $null }
            @{ Case = 'an empty string'; Raw = ''; Expected = $null }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Raw = $Raw; Expected = $Expected } {
                param($Raw, $Expected)
                $G = ConvertTo-OERGroup -InputObject @{ id = 'g-1'; displayName = 'a'; visibility = $Raw }
                if ($null -eq $Expected) { $null -eq $G.Visibility | Should -BeTrue }
                else { $G.Visibility | Should -BeExactly $Expected }
            }
        }

        It 'writes CreatedDateTime as a UTC ISO 8601 string from <Case>' -ForEach @(
            @{ Case = 'a UTC DateTime'; Kind = 'Utc'; Expected = '2026-03-04T05:06:07Z' }
            @{ Case = 'an Unspecified DateTime, taken as UTC and never shifted'; Kind = 'Unspecified'; Expected = '2026-03-04T05:06:07Z' }
            @{ Case = 'a Local DateTime, converted to UTC'; Kind = 'Local'; Expected = $null }
            @{ Case = 'a DateTimeOffset with an offset'; Kind = 'Offset'; Expected = '2026-03-04T03:06:07Z' }
            @{ Case = 'an ISO string with a Z'; Kind = 'StringZ'; Expected = '2026-03-04T05:06:07Z' }
            @{ Case = 'an ISO string with fractional seconds'; Kind = 'StringFraction'; Expected = '2026-03-04T05:06:07Z' }
            @{ Case = 'an ISO string with an offset'; Kind = 'StringOffset'; Expected = '2026-03-04T03:06:07Z' }
            @{ Case = 'an ISO string with no offset, taken as UTC'; Kind = 'StringNoOffset'; Expected = '2026-03-04T05:06:07Z' }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Kind = $Kind; Expected = $Expected } {
                param($Kind, $Expected)
                $Moment = [datetime]::new(2026, 3, 4, 5, 6, 7)
                $Raw = switch ($Kind) {
                    'Utc' { [datetime]::SpecifyKind($Moment, [System.DateTimeKind]::Utc) }
                    'Unspecified' { [datetime]::SpecifyKind($Moment, [System.DateTimeKind]::Unspecified) }
                    'Local' { [datetime]::SpecifyKind($Moment, [System.DateTimeKind]::Local) }
                    'Offset' { [System.DateTimeOffset]::new(2026, 3, 4, 5, 6, 7, [timespan]::FromHours(2)) }
                    'StringZ' { '2026-03-04T05:06:07Z' }
                    'StringFraction' { '2026-03-04T05:06:07.1234567Z' }
                    'StringOffset' { '2026-03-04T05:06:07+02:00' }
                    'StringNoOffset' { '2026-03-04T05:06:07' }
                }
                if ($Kind -eq 'Local') { $Expected = $Raw.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture) }
                $G = ConvertTo-OERGroup -InputObject @{ id = 'g-1'; displayName = 'a'; createdDateTime = $Raw }
                $G.CreatedDateTime | Should -BeOfType [string]
                $G.CreatedDateTime | Should -BeExactly $Expected
            }
        }

        It 'writes CreatedDateTime in invariant form whatever the current culture is' {
            InModuleScope Omnicit.EntraRBAC {
                $Saved = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    # A culture whose time separator and digits differ from the invariant ones.
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('ar-SA')
                    $G = ConvertTo-OERGroup -InputObject @{
                        id = 'g-1'; displayName = 'a'
                        createdDateTime = [datetime]::SpecifyKind([datetime]::new(2026, 3, 4, 5, 6, 7), [System.DateTimeKind]::Utc)
                    }
                } finally {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = $Saved
                }
                $G.CreatedDateTime | Should -BeExactly '2026-03-04T05:06:07Z'
            }
        }

        It 'reads CreatedDateTime as empty from <Case>' -ForEach @(
            @{ Case = 'null'; Raw = $null }
            @{ Case = 'an empty string'; Raw = '' }
            @{ Case = 'white space'; Raw = '   ' }
            @{ Case = 'garbage'; Raw = 'not a date' }
            @{ Case = 'a number'; Raw = 20260304 }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Raw = $Raw } {
                param($Raw)
                $G = ConvertTo-OERGroup -InputObject @{ id = 'g-1'; displayName = 'a'; createdDateTime = $Raw }
                $null -eq $G.CreatedDateTime | Should -BeTrue
            }
        }

        It 'keeps every property in the documented order, the three new ones where the design puts them' {
            InModuleScope Omnicit.EntraRBAC {
                $G = ConvertTo-OERGroup -InputObject @{ id = 'g-1'; displayName = 'a' }
                # The stored properties only: the type data adds the Summary ScriptProperty on top.
                [string[]]$Names = @($G.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } | ForEach-Object { $_.Name })
                $Names | Should -Be @(
                    'Id', 'DisplayName', 'Description', 'MailNickname', 'GroupType', 'SecurityEnabled',
                    'MailEnabled', 'IsAssignableToRole', 'GroupTypes', 'MembershipRule',
                    'MembershipRuleProcessingState', 'OnPremisesSyncEnabled', 'Visibility', 'CreatedDateTime'
                )
            }
        }
    }

    Context 'OnPremisesSyncEnabled (A15)' {
        It 'carries <Case> as <Expected>' -ForEach @(
            @{ Case = 'a synced group (true)'; Raw = @{ id = 'g-1'; displayName = 'a'; onPremisesSyncEnabled = $true }; Expected = $true }
            @{ Case = 'a no-longer-synced group (false)'; Raw = @{ id = 'g-1'; displayName = 'a'; onPremisesSyncEnabled = $false }; Expected = $false }
            @{ Case = 'a cloud group (null)'; Raw = @{ id = 'g-1'; displayName = 'a'; onPremisesSyncEnabled = $null }; Expected = $null }
            @{ Case = 'an answer without the key'; Raw = @{ id = 'g-1'; displayName = 'a' }; Expected = $null }
            @{ Case = 'a non-boolean value'; Raw = @{ id = 'g-1'; displayName = 'a'; onPremisesSyncEnabled = 'false' }; Expected = $null }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Raw = $Raw; Expected = $Expected } {
                param($Raw, $Expected)
                $G = ConvertTo-OERGroup -InputObject $Raw
                @($G.PSObject.Properties.Name) | Should -Contain 'OnPremisesSyncEnabled'
                if ($null -eq $Expected) { $G.OnPremisesSyncEnabled | Should -BeNullOrEmpty }
                else { $G.OnPremisesSyncEnabled | Should -BeOfType [bool]; $G.OnPremisesSyncEnabled | Should -Be $Expected }
            }
        }
    }
}
