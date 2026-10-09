BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Test-OERGroupOnPremisesSynced' {
    It 'answers <Expected> for <Case>' -ForEach @(
        @{ Case = 'OnPremisesSyncEnabled true'; Group = [PSCustomObject]@{ OnPremisesSyncEnabled = $true }; Expected = $true }
        @{ Case = 'OnPremisesSyncEnabled false'; Group = [PSCustomObject]@{ OnPremisesSyncEnabled = $false }; Expected = $false }
        @{ Case = 'OnPremisesSyncEnabled null'; Group = [PSCustomObject]@{ OnPremisesSyncEnabled = $null }; Expected = $false }
        @{ Case = 'no OnPremisesSyncEnabled property'; Group = [PSCustomObject]@{ Id = 'g-1' }; Expected = $false }
        @{ Case = 'the string True'; Group = [PSCustomObject]@{ OnPremisesSyncEnabled = 'True' }; Expected = $false }
        @{ Case = 'the number 1'; Group = [PSCustomObject]@{ OnPremisesSyncEnabled = 1 }; Expected = $false }
        @{ Case = 'a null group'; Group = $null; Expected = $false }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Group = $Group; Expected = $Expected } {
            param($Group, $Expected)
            $R = Test-OERGroupOnPremisesSynced -Group $Group
            $R | Should -BeOfType [bool]
            $R | Should -Be $Expected
        }
    }

    It 'reads the converted group that ConvertTo-OERGroup builds' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERGroupOnPremisesSynced -Group (ConvertTo-OERGroup -InputObject @{ id = 'g-1'; onPremisesSyncEnabled = $true }) | Should -BeTrue
            Test-OERGroupOnPremisesSynced -Group (ConvertTo-OERGroup -InputObject @{ id = 'g-1'; onPremisesSyncEnabled = $null }) | Should -BeFalse
        }
    }

    Context 'single owner (cohort)' {
        # The rule "a live group is synchronized" has ONE owner. Any member access spelled
        # OnPremisesSyncEnabled (any case) in source/ outside these two files is a second reading of it.
        It 'reads OnPremisesSyncEnabled only in ConvertTo-OERGroup and Test-OERGroupOnPremisesSynced' {
            $Root = Join-Path $PSScriptRoot '../../../source'
            $Allowed = @('ConvertTo-OERGroup.ps1', 'Test-OERGroupOnPremisesSynced.ps1')
            $Hits = foreach ($F in Get-ChildItem -Path $Root -Recurse -Filter '*.ps1') {
                $Ast = [System.Management.Automation.Language.Parser]::ParseFile($F.FullName, [ref]$null, [ref]$null)
                $Found = $Ast.FindAll({
                        param($N)
                        $N -is [System.Management.Automation.Language.MemberExpressionAst] -and
                        $N.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                        $N.Member.Value -ieq 'OnPremisesSyncEnabled'
                    }, $true)
                foreach ($H in $Found) { [PSCustomObject]@{ File = $F.Name; Line = $H.Extent.StartLineNumber } }
            }
            $Outside = @($Hits | Where-Object { $_.File -notin $Allowed })
            $Outside | ForEach-Object { "$($_.File):$($_.Line)" } | Should -BeNullOrEmpty
            foreach ($A in $Allowed) {
                @($Hits | Where-Object File -eq $A).Count | Should -BeGreaterThan 0 -Because "$A is a listed owner and must really read the property"
            }
        }
    }
}
