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

    # Az.Accounts is here for the TEST environment, not for run time: the module never calls an
    # Az cmdlet except the guarded Disconnect-AzAccount in Disconnect-OER, and it is absent from
    # the manifest's RequiredModules for that reason. Pester's Mock resolves the command it is
    # given and throws when it cannot, so TWO separate test needs depend on this entry:
    #
    #   1. tests/Unit/Public/Disconnect-OER.Tests.ps1 mocks Disconnect-AzAccount in BeforeEach
    #      (as does Initialize-OERAuth.Tests.ps1 in three places). That mock also keeps a local
    #      run from tearing down the operator's real Az context.
    #   2. tests/Unit/Private/Initialize-OERAuth.Tests.ps1 mocks Connect-AzAccount and asserts
    #      Should -Invoke ... -Times 0. That negative assertion is the test-level PROOF that
    #      -IncludeARM never establishes an Az context -- the premise Az.Resources was removed on.
    #
    # DO NOT remove this entry if Disconnect-OER ever stops calling Disconnect-AzAccount. Reason 1
    # is the visible one and that change would retire it; reason 2 survives untouched. Removing
    # Az.Accounts makes the Mock Connect-AzAccount line throw, and "fixing" that by deleting the
    # mock and its -Times 0 assertion leaves a GREEN suite with the proof gone.
    # See docs/development/rationale.md#dependencies.
    'Az.Accounts'                    = 'latest'
}
