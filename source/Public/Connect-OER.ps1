function Connect-OER {
    <#
    .SYNOPSIS
    Authenticates to Microsoft Graph (and optionally Azure) for Omnicit.EntraRBAC.

    .DESCRIPTION
    Establishes the authentication context used by all OER cmdlets by delegating to the private
    Initialize-OERAuth entry point. It supports interactive browser sign-in, device code, managed
    identity, app registration with a client secret, and app registration with a client certificate,
    selected by the credential switch in use. A tenant can be supplied directly by id or resolved
    from a stored Tenant Profile via -TenantAlias; -TenantAlias combines with any credential
    selector (interactive, device code, managed identity, client secret, or client certificate) and
    is mutually exclusive with -TenantId. With -IncludeARM an Azure Resource Manager token is also
    acquired, which is what the module's own Azure cmdlets use; it does NOT establish an Az
    PowerShell context, so Az module cmdlets are not signed in by it. Calling Connect-OER explicitly
    is optional because OER cmdlets initialize authentication automatically on first use.

    -Environment selects the sovereign cloud to sign in to and to call. It defaults to the worldwide
    commercial cloud, which is also the cloud a Microsoft 365 GCC tenant runs on: GCC is 'Global' and
    needs no cloud selection. Only GCC High and DoD ('USGov' and 'USGovDoD') and a 21Vianet tenant
    ('China') are separate boundaries. The cloud is part of the session, so every later cmdlet in the
    session keeps calling the cloud it was established in; switching clouds re-authenticates rather
    than reusing a token minted at the previous cloud's authority. With -TenantAlias, a stored Tenant
    Profile's own Environment (set via New-/Set-OERConfiguration) is used automatically when
    -Environment is not supplied on the command line, so an operator managing both commercial and
    sovereign-cloud tenants does not have to remember, and pass, which is which on every call; an
    explicit -Environment always overrides the profile's stored value.

    Connect-OER is idempotent while the Microsoft Graph PowerShell SDK session in the process is
    still the one the module connected: calling it again for the same tenant and credential then
    returns from the cached session without re-authenticating. Over a session that another
    Connect-MgGraph has replaced, or one that has been closed (by Disconnect-MgGraph, for example),
    it signs in again. Omitting both -TenantId and -TenantAlias targets the tenant of the current
    session rather than starting a fresh tenant-agnostic sign-in, so a bare Connect-OER -Interactive
    issued after Connect-OER -TenantId A -Interactive still resolves to tenant A instead of an
    unlabelled default. To sign in to a different tenant, pass an explicit -TenantId (or
    -TenantAlias). A client secret sign-in for the same application also needs -Force to move to
    another tenant in the same PowerShell session: AzAuth keeps its credential for the whole
    process, and Disconnect-OER clears this module's session and the Graph SDK session the module
    connected, not that credential.

    An access token lasts about an hour (Microsoft Entra ID gives one a default lifetime of 60 to
    90 minutes), so a longer run has to renew it. Where the sign-in type allows it, the module
    renews a token when a command starts within five minutes of the token's expiry, and in the
    middle of a command when Microsoft Graph or Azure Resource Manager rejects it with 401, after
    which the rejected request is sent once more. A renewal signs in again: an interactive session
    opens the browser, so a long run asks you to sign in about once an hour (choose the account the
    session signed in with; the account picker also offers other accounts of the same tenant, and
    the command then carries on as the one you pick), and a device code session prints a new code to
    enter. A managed identity renews with no prompt and is the only sign-in that renews unattended.
    A client secret or certificate session is not renewed, since the module never keeps the secret
    or certificate: once the token has expired a request is refused with
    AppOnlyTokenRefreshUnsatisfiable, and a command that starts within five minutes of its expiry,
    or later, fails to sign in with AppOnlySessionCredentialUnavailable, until Connect-OER is run
    with the secret or certificate again. A renewal nobody completes fails like any other sign-in:
    the request it was for is not sent, and the session is left uncertain. Before a long run, run
    Connect-OER -Force with the session's own sign-in parameters, so that it starts with a new
    token: a plain Connect-OER with the same sign-in returns the session it has while the token has
    more than five minutes left, and a bare Connect-OER -Force signs in interactively. Stay at the
    keyboard during an interactive or device code run. An app-only run renews only between
    commands, so run Connect-OER -Force with the secret or certificate before each command and keep
    each command shorter than a token's lifetime. See about_Omnicit.EntraRBAC, LONG RUNS.

    Connect-OER also sets up a Microsoft Graph PowerShell SDK session in the current process: it
    calls Connect-MgGraph with the module's token, and so does the automatic sign-in of any other
    OER cmdlet. Disconnect-OER closes that session, and leaves one another Connect-MgGraph started,
    with a warning.

    If another Connect-MgGraph -- your own, or another tool's -- replaces the module's session in
    the same process, the next OER cmdlet sends nothing: it refuses its Microsoft Graph calls with a
    GraphSessionChanged error instead of sending them under that session, and its Azure Resource
    Manager calls with a SignInRefused error. An error can be reported more than once for one
    cmdlet. The module never switches the session back by itself.
    Run Connect-OER with the same sign-in the session used -- for an app-only session, its
    certificate or client secret, since a bare Connect-OER signs in interactively -- to connect the
    module again, which takes the session back and so replaces the other one, or use a new
    PowerShell process. If the session is closed with Disconnect-MgGraph instead of Disconnect-OER,
    the next OER cmdlet signs in again by itself, except on an app-only session (client secret or
    certificate), which reports AppOnlySessionCredentialUnavailable until Connect-OER is run with
    the secret or certificate.

    More generally, an OER cmdlet whose own sign-in fails or is refused -- one that names another
    tenant with -TenantId and cannot sign in to it, for example -- sends no Microsoft Graph or Azure
    Resource Manager request: each request it then attempts is refused with a SignInRefused error
    (or, in the case above, GraphSessionChanged for a Microsoft Graph request) instead of going out
    under the session an earlier sign-in left. A cmdlet it calls, or a neighbour in the same
    pipeline, that signs in successfully does not change that. Run Connect-OER, or a new command
    whose sign-in succeeds, to send requests again. Connect-OER run inside such a command's output,
    as in Invoke-OERStructure -TenantId B -Path x.json | ForEach-Object { Connect-OER -TenantId A },
    is refused too, with a SignInRefused error and before any token request; run as a statement of
    its own, it signs in as before. An OER command whose sign-in another command in the same
    pipeline later replaced with a different tenant or identity sends nothing more either: each
    request made while it runs is refused with a SignInSuperseded error. One pipeline works in one
    tenant with one identity, so run such commands as separate statements. And after a sign-in that
    failed or was refused -- a Connect-OER among them, including one refused before it signs in, such
    as an unknown or empty -TenantAlias or an empty -TenantId -- the module's session may not be the
    one that sign-in asked for (usually it is the previous session, or none), so a later OER command
    that names no tenant sends nothing: its sign-in is refused with a SignInRefused error that says
    so. A command that names its tenant with -TenantId, a successful Connect-OER, or Disconnect-OER
    makes the module send again.

    .PARAMETER TenantId
    The Entra ID tenant GUID or verified domain to authenticate against. Mutually exclusive with
    -TenantAlias. An empty, whitespace or $null -TenantId -- typed, or read from data such as an empty
    CSV cell -- is rejected with an InvalidTenantId error rather than read as no tenant, and leaves the
    session uncertain like any other refused sign-in. Omit -TenantId and -TenantAlias altogether to
    sign in to the current session's tenant.

    .PARAMETER TenantAlias
    The alias of a stored Tenant Profile from which the tenant id is resolved. Combines with any
    credential selector (-Interactive, -DeviceCode, -ManagedIdentity, or the client secret and
    client certificate parameters) and is mutually exclusive with -TenantId. Accepts pipeline input
    by property name, so Get-OERConfiguration | Connect-OER binds automatically. The alias becomes a
    file name on disk, so it is restricted to letters, digits, dot, underscore and hyphen; anything
    else is rejected with an InvalidTenantAlias error. An empty alias, typed or piped, is rejected
    with InvalidTenantAlias too, and leaves the session uncertain like any other refused sign-in.

    .PARAMETER Interactive
    Use interactive browser sign-in (delegated). This is the default when no credential is supplied.

    .PARAMETER DeviceCode
    Use device-code sign-in, suitable for headless or remote sessions. Every device code sign-in
    prints a new code to enter, for the Microsoft Graph and the Azure Resource Manager token alike
    (two with -IncludeARM), and so does every renewal of the token: the module makes AzAuth build
    a new credential each time. A later device code sign-in in the same PowerShell process
    therefore no longer reuses the credential AzAuth keeps for the process, which used to make it
    never return, with no code printed and no error, and it does not need -Force for that. Each
    code has to be entered, so a long device code run needs someone at the keyboard. See
    about_Omnicit.EntraRBAC, SWITCHING TENANTS and LONG RUNS.

    .PARAMETER ManagedIdentity
    Use an Azure managed identity. Combine with -ClientId for a user-assigned identity.

    .PARAMETER ClientId
    The application (client) id to authenticate with. For client secret, client certificate, or a
    user-assigned managed identity it selects the app registration. For interactive or device-code
    sign-in it is optional: when supplied, delegated sign-in uses your own app registration (which
    must expose the required delegated Graph permissions) instead of the default Microsoft Graph
    Command Line Tools client -- useful to obtain a dedicated service-protection (throttling) bucket
    separate from the shared default client.

    .PARAMETER ClientSecret
    A SecureString containing the application client secret used for app-registration sign-in.
    The module converts it to plain text to hand it to AzAuth's Get-AzToken, whose -ClientSecret
    parameter is a string, once for each token it requests (the Graph token, and the ARM token with
    -IncludeARM). On a machine where PowerShell module logging covers AzAuth, that value is recorded
    in plain text in the module logging event (Event 4103). Prefer -Certificate, -CertificatePath or
    -ManagedIdentity.

    .PARAMETER Certificate
    An in-memory X509Certificate2 used for certificate-based app-registration sign-in.

    .PARAMETER CertificatePath
    A path to a certificate file used for certificate-based app-registration sign-in.

    .PARAMETER IncludeARM
    Also acquire an Azure Resource Manager token, so the module's Azure cmdlets can call ARM without
    a second sign-in. The module sends that token itself and never calls Connect-AzAccount, so this
    does not create an Az PowerShell context and does not sign in any Az module cmdlet.

    .PARAMETER BasePath
    Directory holding the Tenant Profile PSD1 files, matching the -BasePath parameter on all four
    *-OERConfiguration cmdlets. Defaults to the current user's home folder plus
    '.config/Omnicit.EntraRBAC/Profiles', which resolves on Windows, Linux and macOS alike.
    Still bindable as -ProfileBasePath, the name this cmdlet shipped with.

    .PARAMETER Environment
    The sovereign cloud to authenticate against and call: 'Global' (the worldwide commercial cloud
    and the default, which is also what a Microsoft 365 GCC tenant runs on), 'USGov' (GCC High),
    'USGovDoD' (DoD) or 'China' (21Vianet). A GCC tenant needs no cloud selection -- leave this
    unset. The chosen cloud becomes part of the session and every later cmdlet calls it.

    .PARAMETER Force
    Signs in again even when a cached session exists, and makes AzAuth discard the credential it
    keeps for the whole PowerShell process and build a new one. Use it to move a client secret
    sign-in for the same application to another tenant in the same session: without it that sign-in
    keeps the tenant it was first made for. A device code sign-in does not need -Force to make
    AzAuth build a new credential: the module does that for every device code sign-in itself. On a
    device code session -Force still signs in again when a cached session exists, which prints new
    codes. It still does not make a device code or managed identity sign-in send the tenant you
    name; see about_Omnicit.EntraRBAC, SWITCHING TENANTS.

    .EXAMPLE
    Connect-OER -TenantId 'contoso.onmicrosoft.com'
    Authenticates interactively to the Contoso tenant.

    .EXAMPLE
    Connect-OER -TenantId $TenantId -ClientId $AppId -CertificatePath $Pfx -IncludeARM
    Authenticates as an app registration using a certificate and also connects to Azure.

    .EXAMPLE
    Connect-OER -TenantId 'contoso.onmicrosoft.com' -Interactive -ClientId $MyAppId
    Signs in interactively using your own app registration instead of the shared default client, so
    Graph calls run under that app's own throttling bucket and delegated permissions.

    .EXAMPLE
    Connect-OER -TenantAlias 'corp' -DeviceCode
    Resolves the tenant id from the stored 'corp' Tenant Profile and signs in with device code, the
    combination a headless or remote session needs.

    .EXAMPLE
    Connect-OER -TenantId 'contoso.onmicrosoft.us' -Environment USGov -IncludeARM
    Signs in to a GCC High tenant against the US Government authority and acquires an Azure Resource
    Manager token for the US Government ARM endpoint. A Microsoft 365 GCC tenant does NOT use this:
    GCC runs on the commercial endpoints, so it signs in with no -Environment at all.

    .EXAMPLE
    Connect-OER -TenantId 'fabrikam.onmicrosoft.com' -ClientId $AppId -ClientSecret $Secret -Force
    Moves a client secret sign-in for the same application from the tenant it was first made for to
    Fabrikam in the same PowerShell session. Without -Force, AzAuth reuses the credential it built
    for the first tenant and the sign-in fails.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Interactive',
        Justification = 'Switch is a parameter-set discriminator; PSCmdlet.ParameterSetName is used instead of the variable.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'DeviceCode',
        Justification = 'Switch is a parameter-set discriminator; PSCmdlet.ParameterSetName is used instead of the variable.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ManagedIdentity',
        Justification = 'Switch is a parameter-set discriminator; PSCmdlet.ParameterSetName is used instead of the variable.')]
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    [OutputType([void])]
    param(
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'DeviceCode')]
        [Parameter(ParameterSetName = 'ClientSecret')]
        [Parameter(ParameterSetName = 'ClientCertificate')]
        [Parameter(ParameterSetName = 'ClientCertificatePath')]
        [Parameter(ParameterSetName = 'ManagedIdentity')]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Interactive', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'DeviceCode', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ManagedIdentity', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ClientSecret', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ClientCertificate', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ClientCertificatePath', ValueFromPipelineByPropertyName)]
        [string]$TenantAlias,

        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$Interactive,

        [Parameter(ParameterSetName = 'DeviceCode', Mandatory)]
        [switch]$DeviceCode,

        [Parameter(ParameterSetName = 'ManagedIdentity', Mandatory)]
        [switch]$ManagedIdentity,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'DeviceCode')]
        [Parameter(ParameterSetName = 'ClientSecret')]
        [Parameter(ParameterSetName = 'ClientCertificate')]
        [Parameter(ParameterSetName = 'ClientCertificatePath')]
        [Parameter(ParameterSetName = 'ManagedIdentity')]
        [string]$ClientId,

        [Parameter(ParameterSetName = 'ClientSecret', Mandatory)]
        [securestring]$ClientSecret,

        [Parameter(ParameterSetName = 'ClientCertificate', Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(ParameterSetName = 'ClientCertificatePath', Mandatory)]
        [string]$CertificatePath,

        [switch]$IncludeARM,

        [Alias('ProfileBasePath')]
        # USERPROFILE is a Windows-only variable and this module declares CompatiblePSEditions
        # Core, so binding this default threw on Linux and macOS before the body ever ran. .NET
        # returns the same directory as $env:USERPROFILE on Windows -- the resolved path is
        # unchanged there -- and the home directory on Linux and macOS.
        [string]$BasePath = (Join-Path $(
                $ProfileRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
                if ($ProfileRoot) { $ProfileRoot } else { $HOME }
            ) '.config/Omnicit.EntraRBAC/Profiles'),

        # Declared LAST on purpose. Positional binding follows DECLARATION order, so a new parameter
        # inserted anywhere above would silently change what an existing positional argument binds
        # to. No default value either: an empty string means 'the caller named no cloud', which
        # Initialize-OERAuth turns into an inherited session cloud or 'Global' -- a default here
        # would overwrite the session's cloud on every bare Connect-OER. -Force follows it, declared
        # even later, since a switch is never bound positionally -- declaring it last disturbs no
        # positional argument regardless of where it lands.
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'DeviceCode')]
        [Parameter(ParameterSetName = 'ClientSecret')]
        [Parameter(ParameterSetName = 'ClientCertificate')]
        [Parameter(ParameterSetName = 'ClientCertificatePath')]
        [Parameter(ParameterSetName = 'ManagedIdentity')]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment,

        [switch]$Force
    )
    process {
        # SEC (A10, BL-89): mark the session uncertain first thing. Connect-OER's own refusals before the
        # sign-in -- InvalidTenantId, AmbiguousTenant, InvalidTenantAlias, TenantAliasNotFound -- leave the
        # session an earlier sign-in left in place, and outside any try the script carries on, so they leave
        # the session uncertain too; a successful sign-in clears it (Initialize-OERAuth).
        $null = Set-OERSessionUncertain -Value $true

        # SEC (A12, BL-94): BOUND, not truthy, as for -TenantAlias below. An empty, whitespace or $null
        # -TenantId -- typed, or read from a CSV cell -- used to name no tenant: Connect-OER signed in to the
        # current session's tenant and, as Connect-OER's sign-in, cleared the session-uncertain marker, so in
        # a loop over tenants the next command that named no tenant applied its row's document in the
        # previous row's tenant. Refused here, after the marker is set, and not with
        # [ValidateNotNullOrEmpty()] as on every other public cmdlet: a parameter binding error never reaches
        # this block, so it would leave the marker as the previous sign-in left it. Connect-OER with neither
        # -TenantId nor -TenantAlias bound still names no tenant, as before.
        if ($PSBoundParameters.ContainsKey('TenantId') -and [string]::IsNullOrWhiteSpace($TenantId)) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "The tenant ID is empty. Name the tenant to sign in to with its tenant ID (a GUID) or a " +
                    "verified domain, or use -TenantAlias: an empty -TenantId is refused rather than read as no " +
                    "tenant, which would sign in to the current session's tenant.")) `
                -ErrorId 'InvalidTenantId' `
                -Category InvalidArgument `
                -TargetObject $TenantId `
                -Cmdlet $PSCmdlet
            return
        }

        if ($TenantId -and $TenantAlias) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Specify either -TenantId or -TenantAlias, not both. -TenantAlias resolves the " +
                    "tenant id from a stored Tenant Profile.")) `
                -ErrorId 'AmbiguousTenant' `
                -Category InvalidArgument `
                -TargetObject $TenantAlias `
                -Cmdlet $PSCmdlet
            return
        }

        $ResolvedTenant = $TenantId
        # SEC (A10, BL-89; final review I1): BOUND, not truthy. An empty, whitespace or $null alias --
        # typed, or read from a profile list or a CSV cell, by the pipeline too -- used to skip this block,
        # so Connect-OER named no tenant: it signed in to the current session's tenant and, as Connect-OER's
        # sign-in, cleared the session-uncertain marker, and in a loop over tenant profiles the next command
        # that named no tenant applied its row's document in the previous row's tenant. A bound alias always
        # reaches the check below, which refuses a blank one, as a blank -TenantId is refused above (A12).
        if ($PSBoundParameters.ContainsKey('TenantAlias')) {
            if (-not (Test-OERTenantAlias -Value $TenantAlias)) {
                [string]$AliasProblem = if ([string]::IsNullOrWhiteSpace($TenantAlias)) {
                    "The tenant alias is empty. Name the stored Tenant Profile to sign in with, or name the " +
                    "tenant with -TenantId: an empty alias is refused rather than read as no alias, which would " +
                    "sign in to the current session's tenant."
                } else {
                    "Tenant alias '$TenantAlias' is not a valid profile name. Use only letters, digits, " +
                    "dot, underscore and hyphen (no path separators and no '..')."
                }
                Write-CmdletError `
                    -Message ([System.Exception]::new($AliasProblem)) `
                    -ErrorId 'InvalidTenantAlias' `
                    -Category InvalidArgument `
                    -TargetObject $TenantAlias `
                    -Cmdlet $PSCmdlet
                return
            }

            $TenantProfile = Get-OERConfiguration -TenantAlias $TenantAlias -BasePath $BasePath
            if (-not $TenantProfile) {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "No usable Tenant Profile for alias '$TenantAlias'. Either no profile file exists " +
                        "for that alias, or one exists and could not be parsed (a TenantProfileMalformed " +
                        "error is reported alongside this one). Create a missing profile with " +
                        "New-OERConfiguration; repair a malformed file on disk, or overwrite its values " +
                        "with Set-OERConfiguration.")) `
                    -ErrorId 'TenantAliasNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $TenantAlias `
                    -Cmdlet $PSCmdlet
                return
            }
            $ResolvedTenant = $TenantProfile.TenantId
        }

        $AuthMethod = switch ($PSCmdlet.ParameterSetName) {
            'DeviceCode'            { 'DeviceCode' }
            'ManagedIdentity'       { 'ManagedIdentity' }
            'ClientSecret'          { 'ClientSecret' }
            'ClientCertificate'     { 'ClientCertificate' }
            'ClientCertificatePath' { 'ClientCertificate' }
            default                 { 'Interactive' }
        }

        # A cloud named explicitly on the command line always wins over one stored on the resolved
        # Tenant Profile; failing that, a profile carrying an Environment (Task 5, issue #81) selects
        # the cloud for this tenant automatically. $TenantProfile is $null on the -TenantId path (no
        # alias was resolved), and member access on $null returns $null rather than throwing, so this
        # is safe whether or not -TenantAlias was used.
        $ResolvedEnvironment = if ($Environment) { $Environment } elseif ($TenantProfile.Environment) { $TenantProfile.Environment } else { $null }

        $AuthParams = @{ TenantId = $ResolvedTenant; AuthMethod = $AuthMethod; IncludeARM = $IncludeARM }
        if ($ClientId)        { $AuthParams.ClientId = $ClientId }
        if ($ClientSecret)    { $AuthParams.ClientSecret = $ClientSecret }
        if ($Certificate)     { $AuthParams.Certificate = $Certificate }
        if ($CertificatePath) { $AuthParams.CertificatePath = $CertificatePath }
        # Forwarded ONLY when a cloud was actually named (explicitly or via the profile), exactly like
        # -ClientId above: forwarding an empty string would fail the ValidateSet on Initialize-OERAuth,
        # and forwarding a 'Global' default would stamp the public cloud over a sovereign session on
        # every cmdlet that does not name one.
        if ($ResolvedEnvironment) { $AuthParams.Environment = $ResolvedEnvironment }
        if ($Force) { $AuthParams.ForceRefresh = $true }
        # SEC (A18): Connect-OER is the operator's explicit instruction to connect, so a Microsoft Graph
        # PowerShell SDK session that another Connect-MgGraph started after the module connected is a
        # cache miss here and is replaced -- the one place the module takes the session back. Every
        # other cmdlet refuses that session with GraphSessionChanged instead; see Initialize-OERAuth.
        $AuthParams.ReclaimGraphSession = $true

        Initialize-OERAuth @AuthParams
    }
}
