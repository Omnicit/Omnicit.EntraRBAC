BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Test-OERDeclaredProperty' {

    It 'returns false for a null node' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredProperty -Node $null -Name 'description' | Should -Be $false
        }
    }

    It 'returns false when the property is absent' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredProperty -Node ([PSCustomObject]@{ displayName = 'x' }) -Name 'description' | Should -Be $false
        }
    }

    It 'returns false when the property is present but null' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredProperty -Node ([PSCustomObject]@{ description = $null }) -Name 'description' | Should -Be $false
        }
    }

    It 'returns true for an explicitly empty string, which is the documented clear value' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredProperty -Node ([PSCustomObject]@{ description = '' }) -Name 'description' | Should -Be $true
        }
    }

    It 'returns true for an empty array, so a declared [] can still assert emptiness' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredProperty -Node ([PSCustomObject]@{ activationEnablement = @() }) -Name 'activationEnablement' | Should -Be $true
        }
    }

    It 'returns true for a declared false, which is a real boolean' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredProperty -Node ([PSCustomObject]@{ requireApproval = $false }) -Name 'requireApproval' | Should -Be $true
        }
    }

    It 'returns true for the integer zero' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredProperty -Node ([PSCustomObject]@{ durationInDays = 0 }) -Name 'durationInDays' | Should -Be $true
        }
    }

    It 'matches the property name case-insensitively' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredProperty -Node ([PSCustomObject]@{ MailNickname = 'a' }) -Name 'mailNickname' | Should -Be $true
        }
    }

    It 'reads a ConvertFrom-Json node carrying an explicit null' {
        InModuleScope $script:moduleName {
            $Node = '{ "description": null, "displayName": "x" }' | ConvertFrom-Json
            Test-OERDeclaredProperty -Node $Node -Name 'description' | Should -Be $false
            Test-OERDeclaredProperty -Node $Node -Name 'displayName' | Should -Be $true
        }
    }
}

Describe 'Declared-predicate delegation' {

    BeforeAll {
        # $PSScriptRoot is tests/Unit/Private -- three hops (Private -> Unit -> tests -> repo root) reach
        # the repo root, where 'source' lives as a sibling of 'tests'.
        $script:sourceRoot = Join-Path -Path ($PSScriptRoot | Split-Path | Split-Path | Split-Path) -ChildPath 'source'
    }

    It 'defines the present-AND-non-null expression in exactly one file' {
        $Pattern = [regex]::Escape('-icontains $Name) -and $null -ne $Node.$Name')
        $Hits = @(Get-ChildItem -Path $script:sourceRoot -Recurse -Filter '*.ps1' |
                Where-Object { (Get-Content -Raw -Path $_.FullName) -match $Pattern })
        $Hits.Count | Should -Be 1 -Because (
            'the rule must live only in Test-OERDeclaredProperty; found it in: ' +
            (($Hits.Name | Sort-Object) -join ', '))
        $Hits[0].Name | Should -BeExactly 'Test-OERDeclaredProperty.ps1'
    }

    It 'has every file that carries a nested declared-predicate helper delegating to the owner' {
        $Files = @(
            'Private/Resolve-OERGroupPimPolicyChange.ps1'
            'Private/Resolve-OERRoleManagementPolicyChange.ps1'
            'Private/Resolve-OERAccessReviewChange.ps1'
            'Private/Sync-OERStructureAdministrativeUnit.ps1'
            'Private/Sync-OERStructureRoleAssignment.ps1'
            'Private/Test-OERStructureSchema.ps1'
        )
        $Files.Count | Should -Be 6 -Because 'an empty list would make the loop below assert nothing'
        foreach ($Relative in $Files) {
            $Path = Join-Path -Path $script:sourceRoot -ChildPath $Relative
            Test-Path -Path $Path | Should -Be $true -Because "$Relative must exist"
            (Get-Content -Raw -Path $Path) | Should -Match 'Test-OERDeclaredProperty' -Because (
                "$Relative declares a nested declared-predicate helper and must delegate to the owner")
        }
    }
}
