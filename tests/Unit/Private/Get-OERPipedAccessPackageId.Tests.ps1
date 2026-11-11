BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERPipedAccessPackageId' {
    BeforeEach {
        $script:Ap = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000031'; DisplayName = 'AP' }
        $script:Ap.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackage')
    }

    It 'returns the piped object''s Id when every condition holds' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Ap = $script:Ap } {
            Get-OERPipedAccessPackageId -InputObject $Ap -AccessPackage 'AP' -Expecting | Should -BeExactly '00000000-0000-0000-0000-000000000031'
        }
    }

    It 'returns $null when the command receives no pipeline input' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Ap = $script:Ap } {
            Get-OERPipedAccessPackageId -InputObject $Ap -AccessPackage 'AP' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for a null piped object' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERPipedAccessPackageId -InputObject $null -AccessPackage 'AP' -Expecting | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for an object not tagged as an access package' {
        InModuleScope Omnicit.EntraRBAC {
            $Other = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000031'; DisplayName = 'AP' }
            Get-OERPipedAccessPackageId -InputObject $Other -AccessPackage 'AP' -Expecting | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the Id is not a GUID' {
        InModuleScope Omnicit.EntraRBAC {
            $Other = [pscustomobject]@{ Id = 'AP-1'; DisplayName = 'AP' }
            $Other.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackage')
            Get-OERPipedAccessPackageId -InputObject $Other -AccessPackage 'AP' -Expecting | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the bound name is not the object''s DisplayName (ordinal)' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Ap = $script:Ap } {
            Get-OERPipedAccessPackageId -InputObject $Ap -AccessPackage 'ap' -Expecting | Should -BeNullOrEmpty
            Get-OERPipedAccessPackageId -InputObject $Ap -AccessPackage 'Other' -Expecting | Should -BeNullOrEmpty
        }
    }

    It 'returns the piped object''s Id whether or not -Catalog is involved: no CatalogBound parameter exists' {
        InModuleScope Omnicit.EntraRBAC {
            (Get-Command Get-OERPipedAccessPackageId).Parameters.Keys | Should -Not -Contain 'CatalogBound'
        }
    }
}
