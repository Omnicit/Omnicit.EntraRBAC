function Get-OERGraphServiceRoot {
    <#
    .SYNOPSIS
    Returns the versioned Microsoft Graph service root for the current session's sovereign cloud.

    .DESCRIPTION
    Single owner of the "which cloud is this session in, and what is its Graph service root" rule
    for the small number of call sites that build an absolute '@odata.id' bind reference by hand --
    Graph's $ref navigation endpoints require a fully-qualified URL in the request body, so a
    relative path cannot be used there. Reads the cloud from $script:_OERAuthState.Environment,
    which Initialize-OERAuth populates at the start of every public cmdlet that calls Graph or
    Azure, and defaults to 'Global' when there is no session yet or the cached state carries no
    Environment -- the same default Initialize-OERAuth itself falls back to, so a caller that has
    not yet authenticated (or a session established before this sprint's Environment tracking
    existed) still resolves to the worldwide public cloud. The endpoint lookup itself is delegated
    to Get-OERCloudEndpoint, the single owner of the cloud-to-endpoint table; this helper never
    hardcodes a cloud URL of its own.

    Returns the GraphServiceRoot property, for example 'https://graph.microsoft.com/v1.0'. That
    value carries the API version and has NO trailing slash, so callers build a bind reference by
    concatenating "$Root/directoryObjects/$Id" directly. Do not substitute GraphResource for this
    purpose: it is the token audience, carries a trailing slash, and concatenating a path onto it
    would emit a double slash.

    .EXAMPLE
    "$(Get-OERGraphServiceRoot)/directoryObjects/$PrincipalId"
    Builds an '@odata.id' bind reference rooted at the current session's cloud (or the public cloud
    when there is no session).
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param()

    $SessionEnvironment = if ($script:_OERAuthState -and $script:_OERAuthState.Environment) {
        $script:_OERAuthState.Environment
    } else {
        'Global'
    }
    return (Get-OERCloudEndpoint -Environment $SessionEnvironment).GraphServiceRoot
}
