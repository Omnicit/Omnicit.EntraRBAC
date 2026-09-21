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
    'Az.Resources'                   = 'latest'
    'Microsoft.Graph.Authentication' = 'latest'
}
