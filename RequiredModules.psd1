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

    # Runtime dependencies — bundled by the package task.
    'AzAuth'                         = 'latest'
    'Az.Resources'                   = '9.0.3'
    'Microsoft.Graph.Authentication' = '2.36.0'
}
