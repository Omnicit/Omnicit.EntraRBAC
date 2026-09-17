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
    acquired so Az.Resources cmdlets can be used in the same session. Calling Connect-OER explicitly
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

    Connect-OER is idempotent: calling it again for the same tenant and credential returns from the
    cached session without re-authenticating. Omitting both -TenantId and -TenantAlias targets the
    tenant of the current session rather than starting a fresh tenant-agnostic sign-in, so a bare
    Connect-OER -Interactive issued after Connect-OER -TenantId A -Interactive still resolves to
    tenant A instead of an unlabelled default. To sign in to a different tenant, pass an explicit
    -TenantId (or -TenantAlias). A client secret sign-in for the same application also needs -Force
    to move to another tenant in the same PowerShell session: AzAuth keeps its credential for the
    whole process, and Disconnect-OER clears only this module's session, not that credential.

    .PARAMETER TenantId
    The Entra ID tenant GUID or verified domain to authenticate against. Mutually exclusive with
    -TenantAlias.

    .PARAMETER TenantAlias
    The alias of a stored Tenant Profile from which the tenant id is resolved. Combines with any
    credential selector (-Interactive, -DeviceCode, -ManagedIdentity, or the client secret and
    client certificate parameters) and is mutually exclusive with -TenantId. Accepts pipeline input
    by property name, so Get-OERConfiguration | Connect-OER binds automatically. The alias becomes a
    file name on disk, so it is restricted to letters, digits, dot, underscore and hyphen; anything
    else is rejected with an InvalidTenantAlias error.

    .PARAMETER Interactive
    Use interactive browser sign-in (delegated). This is the default when no credential is supplied.

    .PARAMETER DeviceCode
    Use device-code sign-in, suitable for headless or remote sessions. Known limitation: in a
    PowerShell process where a device-code sign-in has already completed, a further device-code
    sign-in naming a different tenant without -Force never returns -- no device code is printed, no
    error is raised, and Ctrl+C is the only escape, after which the PowerShell session has to be
    exited. Pass -Force on the switching call, or start a new PowerShell session. A first
    device-code sign-in in a process is unaffected, and so is a switch made straight after a
    -IncludeARM sign-in. See about_Omnicit.EntraRBAC, SWITCHING TENANTS.

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

    .PARAMETER Certificate
    An in-memory X509Certificate2 used for certificate-based app-registration sign-in.

    .PARAMETER CertificatePath
    A path to a certificate file used for certificate-based app-registration sign-in.

    .PARAMETER IncludeARM
    Also acquire an Azure Resource Manager token and connect to Azure for Az.Resources cmdlets.

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
    keeps the tenant it was first made for. A device-code sign-in that switches tenants in a process
    where a device-code sign-in has already completed needs it too: without -Force that call never
    returns -- no device code is printed and no error is raised -- and Ctrl+C is the only escape. It
    still does not make a device code or managed identity sign-in send the tenant you name; see
    about_Omnicit.EntraRBAC, SWITCHING TENANTS.

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
        if ($TenantAlias) {
            if (-not (Test-OERTenantAlias -Value $TenantAlias)) {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "Tenant alias '$TenantAlias' is not a valid profile name. Use only letters, digits, " +
                        "dot, underscore and hyphen (no path separators and no '..').")) `
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

        Initialize-OERAuth @AuthParams
    }
}
