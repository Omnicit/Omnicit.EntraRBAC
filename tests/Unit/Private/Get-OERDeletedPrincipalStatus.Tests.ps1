# tests/Unit/Private/Get-OERDeletedPrincipalStatus.Tests.ps1
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

Describe 'Get-OERDeletedPrincipalStatus' {
    # Sprint 11 step 6 (BL-133, A18). A role assignment's principal that a successful getByIds lookup
    # did not return is either among the directory's deleted items (Deleted) or found nowhere
    # (Unresolved). Measured live 2026-10-15: an unknown id answers 404 Request_ResourceNotFound. A read
    # that fails is reported as unread, never as a fact. No id below is version-4 shaped.
    BeforeAll {
        $script:DelId = 'dddd6666-0000-0000-0000-000000000001'
        $script:DelUri = "v1.0/directory/deletedItems/$($script:DelId)"
        # The marker Invoke-OERGraphRequest returns for a declared expected error code.
        $script:NewNotFoundMarker = {
            $Marker = [PSCustomObject]@{
                ExpectedErrorCode = 'Request_ResourceNotFound'; StatusCode = 404
                Message = "Resource '$($script:DelId)' does not exist."; Uri = $script:DelUri
            }
            $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
            $Marker
        }
    }

    It 'reads directory/deletedItems/{id} with the not-found codes declared, and answers Deleted for an object' {
        InModuleScope $script:moduleName -Parameters @{ Id = $script:DelId; Uri = $script:DelUri } {
            param($Id, $Uri)
            Mock Invoke-OERGraphRequest { @{ id = $Id; '@odata.type' = '#microsoft.graph.user'; deletedDateTime = '2026-10-01T00:00:00Z' } }
            $Result = Get-OERDeletedPrincipalStatus -Id $Id
            @($Result.PSObject.Properties.Name) | Should -Be @('Id', 'Status', 'Read', 'Cause')
            "$($Result.Id)|$($Result.Status)|$($Result.Read)|$($Result.Cause)" | Should -Be "$Id|Deleted|True|"
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -ceq "v1.0/directory/deletedItems/$Id" -and
                (@($ExpectedErrorCode) -join ',') -ceq 'Request_ResourceNotFound,ResourceNotFound,NotFound'
            }
        }
    }

    It 'answers Unresolved, read, for the not-found marker' {
        InModuleScope $script:moduleName -Parameters @{ Id = $script:DelId; Marker = (& $script:NewNotFoundMarker) } {
            param($Id, $Marker)
            Mock Invoke-OERGraphRequest { $Marker }
            $Result = Get-OERDeletedPrincipalStatus -Id $Id
            "$($Result.Id)|$($Result.Status)|$($Result.Read)|$($Result.Cause)" | Should -Be "$Id|Unresolved|True|"
        }
    }

    It 'answers Unresolved, not read, with the cause for a failed read, scrubs the record first, writes no error and never throws' {
        InModuleScope $script:moduleName -Parameters @{ Id = $script:DelId } {
            param($Id)
            Mock Invoke-OERGraphRequest { throw 'Insufficient privileges to complete the operation.' }
            Mock Remove-OERErrorRecord { }
            $Errors = $null
            $Result = Get-OERDeletedPrincipalStatus -Id $Id -ErrorVariable Errors
            "$($Result.Id)|$($Result.Status)|$($Result.Read)|$($Result.Cause)" | Should -Be "$Id|Unresolved|False|Insufficient privileges to complete the operation."
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
            # -ErrorVariable also collects the stray the failed read raised inside the call (the engine
            # fills it before any catch runs); the helper itself publishes none.
            @($Errors | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains 'Get-OERDeletedPrincipalStatus' }).Count | Should -Be 0
        }
    }

    It 'answers Unresolved, not read, for an empty answer, which is no object and no marker' {
        InModuleScope $script:moduleName -Parameters @{ Id = $script:DelId } {
            param($Id)
            Mock Invoke-OERGraphRequest { }
            $Result = Get-OERDeletedPrincipalStatus -Id $Id
            "$($Result.Status)|$($Result.Read)" | Should -Be 'Unresolved|False'
            $Result.Cause | Should -Not -BeNullOrEmpty
        }
    }

    It 'caches an answer per id, without regard to letter case, and reads it once' {
        InModuleScope $script:moduleName -Parameters @{ Id = $script:DelId; Marker = (& $script:NewNotFoundMarker) } {
            param($Id, $Marker)
            Mock Invoke-OERGraphRequest { $Marker }
            $Cache = [System.Collections.Generic.Dictionary[string, object]]::new()
            $First = Get-OERDeletedPrincipalStatus -Id $Id -Cache $Cache
            $Second = Get-OERDeletedPrincipalStatus -Id $Id.ToUpperInvariant() -Cache $Cache
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
            "$($Second.Status)|$($Second.Read)" | Should -Be 'Unresolved|True'
            [object]::ReferenceEquals($First, $Second) | Should -BeTrue
            # Keyed on the lower-cased id, so an ordinal dictionary still matches every letter case.
            @($Cache.Keys) | Should -Be @($Id.ToLowerInvariant())
        }
    }

    It 'caches a Deleted answer too' {
        InModuleScope $script:moduleName -Parameters @{ Id = $script:DelId } {
            param($Id)
            Mock Invoke-OERGraphRequest { @{ id = $Id } }
            $Cache = @{}
            $null = Get-OERDeletedPrincipalStatus -Id $Id -Cache $Cache
            (Get-OERDeletedPrincipalStatus -Id $Id -Cache $Cache).Status | Should -Be 'Deleted'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
        }
    }

    It 'does not cache a failed read or an empty answer: the next call reads again' -ForEach @(
        @{ Case = 'a failed read'; Fails = $true }
        @{ Case = 'an empty answer'; Fails = $false }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Id = $script:DelId; Fails = $Fails } {
            param($Id, $Fails)
            if ($Fails) { Mock Invoke-OERGraphRequest { throw 'Service unavailable (503)' } } else { Mock Invoke-OERGraphRequest { } }
            Mock Remove-OERErrorRecord { }
            $Cache = @{}
            $null = Get-OERDeletedPrincipalStatus -Id $Id -Cache $Cache
            $Again = Get-OERDeletedPrincipalStatus -Id $Id -Cache $Cache
            $Again.Read | Should -BeFalse
            Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
            $Cache.Count | Should -Be 0
        }
    }

    It 'reads every time without a cache' {
        InModuleScope $script:moduleName -Parameters @{ Id = $script:DelId; Marker = (& $script:NewNotFoundMarker) } {
            param($Id, $Marker)
            Mock Invoke-OERGraphRequest { $Marker }
            $null = Get-OERDeletedPrincipalStatus -Id $Id
            $null = Get-OERDeletedPrincipalStatus -Id $Id
            Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
        }
    }

    It 'escapes the id into the path, so an id that is not a plain object id cannot change the request' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ id = 'x' } }
            $null = Get-OERDeletedPrincipalStatus -Id 'a/b?c'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq 'v1.0/directory/deletedItems/a%2Fb%3Fc' }
        }
    }
}
