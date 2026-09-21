@{
    InvokeBuild           = 'latest'
    PSScriptAnalyzer      = 'latest'
    Pester                = 'latest'
    ModuleBuilder         = 'latest'
    Configuration         = 'latest'
    Metadata              = 'latest'
    ChangelogManagement   = 'latest'
    Sampler               = 'latest'
    'Sampler.GitHubTasks' = 'latest'

    # Declared explicitly although Sampler.GitHubTasks already pulls it in transitively. Sampler's
    # Publish_release_to_GitHub task is declared -if ($GitHubToken -and (Get-Module -Name
    # PowerShellForGitHub -ListAvailable)) and so SKIPS SILENTLY when the module is absent. A
    # transitive dependency that decides whether a release step runs at all is one worth being
    # able to see in the file that resolves it.
    PowerShellForGitHub   = 'latest'

    # Modules the module under test loads at run time. They are resolved into
    # output/RequiredModules so the build and test environment can import Omnicit.EntraRBAC from a
    # clean clone -- they are NOT bundled into anything the package task produces. The built module
    # under output/module/ holds only this module's own files, and a consumer installs these from
    # the manifest's own RequiredModules floors instead.
    'AzAuth'                         = 'latest'
    'Microsoft.Graph.Authentication' = 'latest'

    # Az.Accounts is here for the TEST environment, not for run time. The module calls NO
    # Az.Accounts cmdlet at all -- not one -- which is why no Az module appears in the manifest's
    # RequiredModules, and tests/QA/sourcehygiene.tests.ps1 holds that true at SOURCE level with an
    # AST walk that needs nothing installed in order to run.
    #
    # The entry stays because TWO NEGATIVE proofs are built on mocks, and Pester's Mock resolves the
    # command it is given and throws when it cannot. Without Az.Accounts on PSModulePath neither
    # assertion can even be written:
    #
    #   1. tests/Unit/Public/Disconnect-OER.Tests.ps1 asserts
    #      Should -Invoke Disconnect-AzAccount -Times 0, proving Disconnect-OER leaves an Az
    #      session the operator started alone. Its mock also keeps a reintroduced call from
    #      tearing down the operator's real Az context during a local run.
    #      (Initialize-OERAuth.Tests.ps1 mocks Disconnect-AzAccount in three places for the same
    #      protection.)
    #   2. tests/Unit/Private/Initialize-OERAuth.Tests.ps1 asserts
    #      Should -Invoke Connect-AzAccount -Times 0, the test-level proof that -IncludeARM never
    #      establishes an Az context -- the premise Az.Resources was removed on.
    #
    # On 2026-09-21 Disconnect-OER stopped calling Disconnect-AzAccount (Philip's decision: the
    # module establishes no Az context, so the call could only ever reach the operator's own
    # session). Reason 1 was INVERTED by that change, not retired -- its assertion went from
    # -Times 1 to -Times 0 and needs the command to resolve exactly as much as before. Do not read
    # "Disconnect-OER no longer calls it" as "this entry is dead".
    #
    # Removing Az.Accounts makes both Mock lines throw, and "fixing" that by deleting the mocks and
    # their -Times 0 assertions leaves a GREEN suite with both proofs gone.
    # See docs/development/rationale.md#dependencies.
    'Az.Accounts'                    = 'latest'
}
