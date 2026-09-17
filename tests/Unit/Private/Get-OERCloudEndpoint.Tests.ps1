BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERCloudEndpoint' {

    Context 'table contents' {
        BeforeAll {
            $script:ExpectedTable = @{
                Global    = @{
                    Environment      = 'Global'
                    AuthorityHost    = 'https://login.microsoftonline.com/'
                    GraphResource    = 'https://graph.microsoft.com/'
                    GraphEnvironment = 'Global'
                    GraphServiceRoot = 'https://graph.microsoft.com/v1.0'
                    ArmResource      = 'https://management.azure.com/'
                    ArmHost          = 'https://management.azure.com'
                }
                USGov     = @{
                    Environment      = 'USGov'
                    AuthorityHost    = 'https://login.microsoftonline.us/'
                    GraphResource    = 'https://graph.microsoft.us/'
                    GraphEnvironment = 'USGov'
                    GraphServiceRoot = 'https://graph.microsoft.us/v1.0'
                    ArmResource      = 'https://management.usgovcloudapi.net/'
                    ArmHost          = 'https://management.usgovcloudapi.net'
                }
                USGovDoD  = @{
                    Environment      = 'USGovDoD'
                    AuthorityHost    = 'https://login.microsoftonline.us/'
                    GraphResource    = 'https://dod-graph.microsoft.us/'
                    GraphEnvironment = 'USGovDoD'
                    GraphServiceRoot = 'https://dod-graph.microsoft.us/v1.0'
                    ArmResource      = 'https://management.usgovcloudapi.net/'
                    ArmHost          = 'https://management.usgovcloudapi.net'
                }
                China     = @{
                    Environment      = 'China'
                    AuthorityHost    = 'https://login.chinacloudapi.cn/'
                    GraphResource    = 'https://microsoftgraph.chinacloudapi.cn/'
                    GraphEnvironment = 'China'
                    GraphServiceRoot = 'https://microsoftgraph.chinacloudapi.cn/v1.0'
                    ArmResource      = 'https://management.chinacloudapi.cn/'
                    ArmHost          = 'https://management.chinacloudapi.cn'
                }
            }
        }

        It 'returns every table cell verbatim for <_>' -ForEach @('Global', 'USGov', 'USGovDoD', 'China') {
            $Cloud = $_
            $Expected = $script:ExpectedTable[$Cloud]
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Cloud = $Cloud; Expected = $Expected } {
                param($Cloud, $Expected)

                $Actual = Get-OERCloudEndpoint -Environment $Cloud

                $Actual.Environment | Should -BeExactly $Expected.Environment
                $Actual.AuthorityHost | Should -BeExactly $Expected.AuthorityHost
                $Actual.GraphResource | Should -BeExactly $Expected.GraphResource
                $Actual.GraphEnvironment | Should -BeExactly $Expected.GraphEnvironment
                $Actual.GraphServiceRoot | Should -BeExactly $Expected.GraphServiceRoot
                $Actual.ArmResource | Should -BeExactly $Expected.ArmResource
                $Actual.ArmHost | Should -BeExactly $Expected.ArmHost
            }
        }

        It 'tags the returned object Omnicit.EntraRBAC.CloudEndpoint' {
            InModuleScope Omnicit.EntraRBAC {
                $Actual = Get-OERCloudEndpoint -Environment 'China'
                $Actual.PSObject.TypeNames | Should -Contain 'Omnicit.EntraRBAC.CloudEndpoint'
            }
        }
    }

    Context 'public-cloud literal parity with Initialize-OERAuth.ps1' {
        # Task 2 shipped this Context as a drift guard between two independent copies of the same two
        # strings: the table below and the hardcoded $GraphResource / $ArmResource locals that
        # Initialize-OERAuth carried at the time. Task 3 wired Initialize-OERAuth to this table, so
        # there is no second copy left to drift -- and the guard inverts. What has to stay true now
        # is that Initialize-OERAuth carries NO cloud URL of its own and reads both resources from
        # here, which is what the two tests below assert. The public-cloud values themselves are
        # still pinned as exact literals, one file over, in the endpoint table tests above.
        BeforeAll {
            # Blank out every COMMENT token, preserving offsets, and scan what is left. Stripping
            # '^\s*#' lines instead would miss a '<# ... #>' block entirely -- including the
            # comment-based help, where a later task documenting an endpoint would make the offender
            # scan below go spuriously red on correct code. The PowerShell tokenizer knows exactly
            # where a comment starts and ends; a line-shape regex does not.
            function Remove-OERCommentRegion {
                param([string]$Text)

                $Tokens = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$null)

                $Builder = [System.Text.StringBuilder]::new($Text)
                # Reverse order is not needed since each span is replaced by an EQUAL number of
                # spaces, so every later offset stays valid.
                foreach ($Token in @($Tokens | Where-Object { $_.Kind -eq 'Comment' })) {
                    $Start = $Token.Extent.StartOffset
                    $Length = $Token.Extent.EndOffset - $Start
                    $null = $Builder.Remove($Start, $Length).Insert($Start, (' ' * $Length))
                }
                $Builder.ToString()
            }

            function Get-OERCloudUrlOffender {
                param([string]$Code)

                @(
                    [regex]::Matches($Code, "'(https://[^']*)'") |
                        ForEach-Object { $_.Groups[1].Value } |
                        Where-Object {
                            $_ -match 'graph\.microsoft\.|management\.(azure|usgovcloudapi|chinacloudapi)\.|login\.(microsoftonline|chinacloudapi)\.'
                        }
                )
            }

            $InitializeOERAuthPath = Join-Path $PSScriptRoot '../../../source/Private/Initialize-OERAuth.ps1'
            $script:InitializeOERAuthPath = (Resolve-Path -LiteralPath $InitializeOERAuthPath).Path
            $script:InitializeOERAuthText = Get-Content -LiteralPath $script:InitializeOERAuthPath -Raw
            $script:InitializeOERAuthCode = Remove-OERCommentRegion -Text $script:InitializeOERAuthText
        }

        It 'reads both resource strings from Get-OERCloudEndpoint instead of hardcoding them' {
            $script:InitializeOERAuthCode | Should -Match '\$GraphResource\s*=\s*\$Endpoint\.GraphResource'
            $script:InitializeOERAuthCode | Should -Match '\$ArmResource\s*=\s*\$Endpoint\.ArmResource'
            $script:InitializeOERAuthCode | Should -Match 'Get-OERCloudEndpoint\s+-Environment\s+\$EffectiveEnvironment'
        }

        It 'carries no cloud endpoint URL literal of its own' {
            # Every Graph, ARM and authority host must come from the table, so a bare https://
            # literal naming one of those hosts in executable code is a second copy by definition.
            (Get-OERCloudUrlOffender -Code $script:InitializeOERAuthCode) -join ', ' | Should -BeExactly ''
        }

        # Guards the guard. Without these two fixtures the scan above could quietly stop looking at
        # anything at all -- a comment stripper that blanked the WHOLE file would report zero
        # offenders and pass -- and a stripper that missed block comments would fail correct code.
        It 'ignores a cloud URL inside a block comment but still catches one in live code' {
            $Fixture = @'
function Test-OERFixture {
    <#
    .SYNOPSIS
    Prose that names 'https://graph.microsoft.com/' inside a block comment.
    #>
    # And a line comment naming 'https://login.microsoftonline.us/' too.
    $FromTheTable = (Get-OERCloudEndpoint -Environment 'Global').GraphResource
    return $FromTheTable
}
'@
            $Code = Remove-OERCommentRegion -Text $Fixture
            Get-OERCloudUrlOffender -Code $Code | Should -BeNullOrEmpty

            $Offending = $Fixture -replace [regex]::Escape("(Get-OERCloudEndpoint -Environment 'Global').GraphResource"),
                "'https://graph.microsoft.com/'"
            $Offending | Should -Not -Be $Fixture -Because 'the fixture edit must actually have taken effect'

            $OffendingCode = Remove-OERCommentRegion -Text $Offending
            Get-OERCloudUrlOffender -Code $OffendingCode | Should -Be @('https://graph.microsoft.com/')
        }
    }

    Context 'trailing-slash shape' {
        It 'never ends GraphServiceRoot in a slash for <_>' -ForEach @('Global', 'USGov', 'USGovDoD', 'China') {
            $Cloud = $_
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                (Get-OERCloudEndpoint -Environment $Cloud).GraphServiceRoot.EndsWith('/') | Should -BeFalse
            }
        }

        It 'always ends GraphResource in a slash for <_>' -ForEach @('Global', 'USGov', 'USGovDoD', 'China') {
            $Cloud = $_
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                (Get-OERCloudEndpoint -Environment $Cloud).GraphResource.EndsWith('/') | Should -BeTrue
            }
        }

        It 'never ends ArmHost in a slash for <_>' -ForEach @('Global', 'USGov', 'USGovDoD', 'China') {
            $Cloud = $_
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                (Get-OERCloudEndpoint -Environment $Cloud).ArmHost.EndsWith('/') | Should -BeFalse
            }
        }
    }

    Context 'default and validation' {
        It 'defaults -Environment to Global' {
            InModuleScope Omnicit.EntraRBAC {
                $Default = Get-OERCloudEndpoint
                $Explicit = Get-OERCloudEndpoint -Environment 'Global'
                $Default.Environment | Should -BeExactly 'Global'
                $Default.GraphResource | Should -BeExactly $Explicit.GraphResource
                $Default.ArmResource | Should -BeExactly $Explicit.ArmResource
            }
        }

        It 'makes no Graph or ARM call' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { throw 'should not be called' }
                Mock Invoke-OERArmRequest { throw 'should not be called' }
                Mock Get-AzToken { throw 'should not be called' }
                $null = Get-OERCloudEndpoint -Environment 'USGovDoD'
                Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
                Should -Invoke Invoke-OERArmRequest -Times 0 -Exactly
                Should -Invoke Get-AzToken -Times 0 -Exactly
            }
        }
    }

    Context 'unhandled cloud never falls back silently' {
        <#
            -Environment carries NO ValidateSet on this private helper (see .DESCRIPTION): the
            closed cloud domain is enforced at the PUBLIC boundary instead -- Connect-OER and
            Initialize-OERAuth each attach a ValidateSet naming exactly the four clouds this table
            handles, so no caller reaches this helper with a value a user typed by hand. That
            leaves exactly one place an unsupported value can still arrive here: a future cloud
            added to those outer ValidateSets without a matching case being added to the switch
            below.

            Because this parameter is unvalidated, that scenario is directly reachable through the
            function's own ordinary public surface today -- no scriptblock indirection, no
            module-scope publication needed. Calling Get-OERCloudEndpoint -Environment 'Germany' is
            not a stand-in for the real risk; it IS the real risk, reproduced exactly.
        #>
        It 'throws when asked for a cloud absent from the table' {
            InModuleScope Omnicit.EntraRBAC {
                { Get-OERCloudEndpoint -Environment 'Germany' } | Should -Throw
            }
        }

        It 'throw message names the unhandled cloud' {
            InModuleScope Omnicit.EntraRBAC {
                { Get-OERCloudEndpoint -Environment 'Germany' } | Should -Throw -ExpectedMessage '*Germany*'
            }
        }
    }
}
