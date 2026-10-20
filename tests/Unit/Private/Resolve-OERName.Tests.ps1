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

Describe 'Resolve-OERName' {
    It 'substitutes tokens from a template' {
        InModuleScope $script:moduleName {
            $Name = Resolve-OERName -Template 'role_sec_{area}_{tier}' -Tokens @{ area = 'identity'; tier = 'administrator' }
            $Name | Should -Be 'role_sec_identity_administrator'
        }
    }

    It 'throws when a token in the template has no value' {
        InModuleScope $script:moduleName {
            { Resolve-OERName -Template 'role_sec_{area}_{tier}' -Tokens @{ area = 'identity' } } |
                Should -Throw -ExpectedMessage '*tier*'
        }
    }

    It 'rejects names exceeding the maximum length' {
        InModuleScope $script:moduleName {
            { Resolve-OERName -Template '{name}' -Tokens @{ name = ('x' * 300) } -MaxLength 256 } |
                Should -Throw -ExpectedMessage '*length*'
        }
    }

    It 'rejects disallowed characters when -Strict is set' {
        InModuleScope $script:moduleName {
            { Resolve-OERName -Template '{name}' -Tokens @{ name = 'bad/name' } -Strict } |
                Should -Throw -ExpectedMessage '*character*'
        }
    }

    # BL-139 (R-12): the template is read in ONE pass and each value is inserted as text. A value is never
    # interpreted as a .NET replacement pattern ($$, $&, $`, $', $_, $1 ...), and a value is never read
    # again as a token, so a token-looking value is kept and is not an unresolved token of the template.
    Context 'a value holding a .NET replacement pattern (BL-139)' {
        It 'inserts <Value> literally' -ForEach @(
            @{ Value = '$$' }
            @{ Value = '$&' }
            @{ Value = '$`' }
            @{ Value = '$''' }
            @{ Value = '$_' }
            @{ Value = '$1' }
            @{ Value = '$+' }
            @{ Value = '${name}' }
            @{ Value = 'cost$' }
            @{ Value = 'a$$b$&c$`d$''e$_f$1g' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Value = $Value } {
                param($Value)
                $Name = Resolve-OERName -Template 'pre-{name}-post' -Tokens @{ name = $Value }
                $Name | Should -BeExactly ('pre-' + $Value + '-post')
            }
        }

        It 'inserts each of two tokens literally when both hold a pattern' {
            InModuleScope $script:moduleName {
                $Name = Resolve-OERName -Template '{a}|{b}' -Tokens @{ a = 'x$&y'; b = '$`z' }
                $Name | Should -BeExactly 'x$&y|$`z'
            }
        }

        It 'inserts a pattern value at every occurrence of its token' {
            InModuleScope $script:moduleName {
                Resolve-OERName -Template '{a}-{a}' -Tokens @{ a = '$&' } | Should -BeExactly '$&-$&'
            }
        }
    }

    Context 'a value holding a token-looking text (BL-139)' {
        It 'keeps a value that is another token''s name as text, in either token order' -ForEach @(
            @{ Order = 'value token first' }
            @{ Order = 'value token last' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Order = $Order } {
                param($Order)
                $Tokens = if ($Order -eq 'value token first') { @{ a = '{b}'; b = 'X' } } else { @{ b = 'X'; a = '{b}' } }
                Resolve-OERName -Template '{a}' -Tokens $Tokens | Should -BeExactly '{b}'
                Resolve-OERName -Template '{a}-{b}' -Tokens $Tokens | Should -BeExactly '{b}-X'
            }
        }

        It 'keeps a value that looks like a token no one supplied, and does not report it unresolved' {
            InModuleScope $script:moduleName {
                Resolve-OERName -Template 'role_{area}' -Tokens @{ area = '{unknown}' } | Should -BeExactly 'role_{unknown}'
            }
        }

        It 'still reports a template token without a key, naming only the template''s own tokens' {
            InModuleScope $script:moduleName {
                $Thrown = $null
                try { Resolve-OERName -Template '{a}_{missing}' -Tokens @{ a = '{fromvalue}' } } catch { $Thrown = $PSItem }
                $Thrown | Should -Not -BeNullOrEmpty
                $Thrown.Exception.Message | Should -BeExactly "Naming template '{a}_{missing}' has unresolved token(s): missing. Supply a value for each token."
            }
        }

        It 'names every unresolved token of the template, in template order' {
            InModuleScope $script:moduleName {
                $Thrown = $null
                try { Resolve-OERName -Template '{z}-{a}-{z}' -Tokens @{ other = 'x' } } catch { $Thrown = $PSItem }
                $Thrown | Should -Not -BeNullOrEmpty
                $Thrown.Exception.Message | Should -BeExactly "Naming template '{z}-{a}-{z}' has unresolved token(s): z, a, z. Supply a value for each token."
            }
        }
    }

    Context 'the existing token rules (BL-139 leaves them as they were)' {
        It 'matches a token name without regard to letter case' {
            InModuleScope $script:moduleName {
                Resolve-OERName -Template 'x_{AREA}_{Tier}' -Tokens @{ area = 'identity'; TIER = 'admin' } | Should -BeExactly 'x_identity_admin'
            }
        }

        It 'matches a token name without regard to letter case in a case-sensitive hashtable' {
            InModuleScope $script:moduleName {
                $Tokens = [hashtable]::new()
                $Tokens['Area'] = 'identity'
                Resolve-OERName -Template 'x_{area}' -Tokens $Tokens | Should -BeExactly 'x_identity'
            }
        }

        It 'reads a $null token value as an empty string' {
            InModuleScope $script:moduleName {
                Resolve-OERName -Template 'x_{a}_y' -Tokens @{ a = $null } | Should -BeExactly 'x__y'
            }
        }

        It 'reads a non-string token value as its string form' {
            InModuleScope $script:moduleName {
                Resolve-OERName -Template 'x_{a}' -Tokens @{ a = 42 } | Should -BeExactly 'x_42'
            }
        }

        It 'returns a template without tokens unchanged' {
            InModuleScope $script:moduleName {
                Resolve-OERName -Template 'plain name' -Tokens @{ unused = 'x' } | Should -BeExactly 'plain name'
            }
        }

        It 'checks the length of the resolved name, a pattern value included' {
            InModuleScope $script:moduleName {
                { Resolve-OERName -Template '{name}' -Tokens @{ name = ('$&' * 200) } -MaxLength 256 } |
                    Should -Throw -ExpectedMessage '*exceeds the maximum length of 256*'
                Resolve-OERName -Template '{name}' -Tokens @{ name = ('$&' * 100) } -MaxLength 256 | Should -BeExactly ('$&' * 100)
            }
        }

        It 'applies -Strict to the resolved name, a value that holds a pattern included' {
            InModuleScope $script:moduleName {
                { Resolve-OERName -Template '{name}' -Tokens @{ name = 'a$&b/c' } -Strict } |
                    Should -Throw -ExpectedMessage '*disallowed character*'
                Resolve-OERName -Template '{name}' -Tokens @{ name = 'a$&b' } -Strict | Should -BeExactly 'a$&b'
            }
        }
    }
}
