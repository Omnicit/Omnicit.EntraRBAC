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
    # the manifest's RequiredModules for that reason. But Pester's Mock requires the command to
    # exist, so without Az.Accounts resolved here every It in
    # tests/Unit/Public/Disconnect-OER.Tests.ps1 fails in BeforeEach. The mock is also what keeps a
    # local run from tearing down the operator's real Az context.
    'Az.Accounts'                    = 'latest'
}
