BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERGroupNameIndex' {
    # BL-131 (R-2). The single owner of which groups in the tenant carry a display name: built from
    # groups already read (the export's roster) with no request, or from ONE paged listing of every
    # group's id and display name. It returns the index or the failure and never writes an error
    # record. No id below is version-4 shaped.
    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    Context 'built from -Group' {
        It 'counts two groups whose names match without regard to letter case under one name, and makes no request' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { throw 'no request is expected' }
                $Index = Get-OERGroupNameIndex -Group @(
                    [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Admins' }
                    [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'ADMINS' }
                    [PSCustomObject]@{ Id = '33333333-3333-3333-3333-333333333333'; DisplayName = 'Readers' }
                )
                $Index.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.GroupNameIndex'
                @($Index.PSObject.Properties.Name) | Should -Be @('Read', 'IdsByName', 'Message')
                $Index.Read | Should -BeTrue
                $null -eq $Index.Message | Should -BeTrue
                $Index.IdsByName | Should -BeOfType ([System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]])
                $Index.IdsByName.Count | Should -Be 2
                # Looked up in any letter case.
                @($Index.IdsByName['admins']) | Should -Be @('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
                $Index.IdsByName['aDmInS'].Count | Should -Be 2
                @($Index.IdsByName['Readers']) | Should -Be @('33333333-3333-3333-3333-333333333333')
                Should -Invoke Invoke-OERGraphRequest -Times 0
            }
        }

        It 'skips a blank or white space name, a group without an id, and a null item' {
            InModuleScope Omnicit.EntraRBAC {
                $Index = Get-OERGroupNameIndex -Group @(
                    [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = '' }
                    [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = '   ' }
                    [PSCustomObject]@{ Id = '33333333-3333-3333-3333-333333333333'; DisplayName = $null }
                    [PSCustomObject]@{ Id = ''; DisplayName = 'Admins' }
                    $null
                    [PSCustomObject]@{ Id = '44444444-4444-4444-4444-444444444444'; DisplayName = 'Admins' }
                )
                $Index.Read | Should -BeTrue
                @($Index.IdsByName.Keys) | Should -Be @('Admins')
                @($Index.IdsByName['Admins']) | Should -Be @('44444444-4444-4444-4444-444444444444')
            }
        }

        It 'lists one group once under its name, however often and in whatever letter case its id is given' {
            InModuleScope Omnicit.EntraRBAC {
                $Index = Get-OERGroupNameIndex -Group @(
                    [PSCustomObject]@{ Id = 'AAAAAAAA-1111-1111-1111-111111111111'; DisplayName = 'Admins' }
                    [PSCustomObject]@{ Id = 'aaaaaaaa-1111-1111-1111-111111111111'; DisplayName = 'admins' }
                )
                $Index.IdsByName['Admins'].Count | Should -Be 1
                @($Index.IdsByName['Admins']) | Should -Be @('aaaaaaaa-1111-1111-1111-111111111111')
            }
        }

        It 'returns an empty index that was read, with no request, for an empty list' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { throw 'no request is expected' }
                $Index = Get-OERGroupNameIndex -Group @()
                $Index.Read | Should -BeTrue
                $Index.IdsByName.Count | Should -Be 0
                Should -Invoke Invoke-OERGraphRequest -Times 0
            }
        }
    }

    Context 'read with one paged listing' {
        It 'sends ONE request for every page, selecting the id and the display name, and builds the index from its rows' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest {
                    @{ value = @(
                            @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Admins' }
                            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'admins' }
                            @{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Readers' }
                            @{ id = '44444444-4444-4444-4444-444444444444'; displayName = $null }
                            $null
                        ) }
                }
                $Index = Get-OERGroupNameIndex
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                    $Uri -ceq 'v1.0/groups?$select=id,displayName&$top=999' -and $All -and (-not $Method -or $Method -eq 'GET')
                }
                $Index.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.GroupNameIndex'
                $Index.Read | Should -BeTrue
                $null -eq $Index.Message | Should -BeTrue
                $Index.IdsByName.Count | Should -Be 2
                $Index.IdsByName['ADMINS'].Count | Should -Be 2
                @($Index.IdsByName['Readers']) | Should -Be @('33333333-3333-3333-3333-333333333333')
            }
        }

        It 'returns an empty index that was read when the listing holds no group' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @() } }
                $Index = Get-OERGroupNameIndex
                $Index.Read | Should -BeTrue
                $Index.IdsByName.Count | Should -Be 0
            }
        }

        It 'returns a failed listing as Read false with its message, scrubs the record first, and throws and writes nothing' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { throw 'Insufficient privileges to complete the operation.' }
                Mock Remove-OERErrorRecord { }
                $Errors = $null
                # Under -ErrorAction Stop a thrown or written record would end the call here, so the
                # result arriving at all is the proof that nothing was thrown or written.
                $Index = Get-OERGroupNameIndex -ErrorVariable Errors -ErrorAction Stop
                $Index.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.GroupNameIndex'
                $Index.Read | Should -BeFalse
                $null -eq $Index.IdsByName | Should -BeTrue -Because 'a failed read is never an empty index'
                $Index.Message | Should -BeExactly 'Could not list every group to count the names groups share: Insufficient privileges to complete the operation.'
                # -ErrorVariable also collects the records of the nested calls (the mock's throw among
                # them); none of them was published by this function.
                @($Errors | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains 'Get-OERGroupNameIndex' }).Count | Should -Be 0
                # The catch was reached and scrubbed the record it caught.
                Should -Invoke Remove-OERErrorRecord -Exactly -Times 1 -ParameterFilter {
                    $Record.Exception.Message -eq 'Insufficient privileges to complete the operation.'
                }
            }
        }
    }
}
