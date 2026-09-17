function Initialize-OERAuth {
    <#
    .SYNOPSIS
    The single authentication entry point for Omnicit.EntraRBAC. Acquires Microsoft Graph (and
    optionally Azure Resource Manager) access tokens via the AzAuth module and wires them into
    Connect-MgGraph and Connect-AzAccount.

    .DESCRIPTION
    Every public OER cmdlet that calls Graph or Azure invokes this function at its entry point.
    It is idempotent: when a valid Graph token is already cached for the requested tenant and
    identity (AuthMethod + ClientId) with at least five minutes of remaining lifetime (and, when
    -IncludeARM is set, a cached ARM token), it returns immediately without acquiring new tokens.

    Requests inherit the current session. A caller that omits -TenantId targets the tenant the
    session was established for, and a caller that omits both -AuthMethod and -ClientId reuses the
    credential it was established with, so an ARM cmdlet on an app-only or managed-identity session
    never falls back to an interactive sign-in. An explicitly supplied parameter always wins, and a
    -TenantId naming a different tenant inherits nothing. When there is no session, the defaults are
    an interactive sign-in against 'organizations'. An inherited app-only (ClientSecret or
    ClientCertificate) identity that needs a new token raises a terminating
    AppOnlySessionCredentialUnavailable error rather than prompting, because the credential material
    is deliberately never cached and the token cannot be re-acquired without it.

    Tokens are obtained through AzAuth's Get-AzToken, which supports interactive browser sign-in,
    device code, managed identity, client secret, and client certificate credentials. The chosen
    credential is selected by -AuthMethod and the associated parameters are forwarded to Get-AzToken
    via splatting. The resulting Graph token is wired into Connect-MgGraph -AccessToken, and, when
    -IncludeARM is set, an Azure Resource Manager token is acquired and cached (as a SecureString)
    in $script:_OERAuthState for Invoke-OERArmRequest to send directly as a bearer token. The module
    deliberately does NOT call Connect-AzAccount: Az.Accounts cannot reliably reuse an externally
    acquired access token through Invoke-AzRestMethod, so all ARM calls go through Invoke-OERArmRequest
    with the cached token instead.

    Auth configuration (method, tenant, client id, cloud, and credential material) is cached in
    $script:_OERAuthState so tokens can be silently re-acquired near expiry without re-prompting.

    The tenant each acquired token was actually ISSUED for is recorded beside the requested one, as
    TokenTenantId and ArmTokenTenantId. TenantId keeps naming what the caller asked for, since that
    is what the cache-key predicates compare. When the requested tenant is a canonical GUID and the
    token names a different one, a terminating TenantMismatch error is raised before the token is
    wired into Connect-MgGraph or cached for Azure Resource Manager, so a token minted for another
    tenant never becomes a usable session. A requested tenant given as a verified domain cannot be
    compared against the GUID a token carries, so no mismatch is inferred there -- the granted value
    is recorded and left to speak for itself.

    Before a client secret token request, a warning is written when the token request that last made
    AzAuth build its credential in this PowerShell session was also a client secret request, for the
    same application but a different tenant, and no Force is on the call (neither -ForceRefresh nor
    the one this function adds for a cloud switch). AzAuth keeps the credential it built for that
    tenant for the whole process and reuses it for that application, so the new tenant is not
    reached. After a Microsoft Graph token is acquired for a tenant named by domain, a warning is
    written when the last session established in this PowerShell process named a different tenant --
    any tenant, 'organizations' included -- and that session's token was issued by the same tenant as
    this one; Disconnect-OER does not reset that comparison. Unless the domain is a name of the
    issuing tenant, the sign-in did not switch tenants, and naming the tenant by its GUID turns the
    same situation into the TenantMismatch refusal instead. A sign-in that names no tenant is not
    checked, and neither is the first sign-in in a process or the first after Omnicit.EntraRBAC is
    re-imported. Neither warning refuses the sign-in, but a caller running with -WarningAction Stop
    or $WarningPreference = 'Stop' is stopped at the warning: the first one before its token request
    is made, the second one before Connect-MgGraph is called and before the session state is
    rebuilt.

    On the DeviceCode flow the sign-in instruction that carries the user code is re-emitted on the
    INFORMATION stream instead of being left on the warning stream where AzAuth writes it. It is the
    primary interaction, not a warning: a caller running with -WarningAction SilentlyContinue never
    saw the code and the sign-in appeared to hang. Only the device-code path is treated this way;
    every other credential type calls Get-AzToken exactly as before.

    -Environment selects the sovereign cloud. Every endpoint that follows from it -- the Graph token
    audience, the Graph environment name handed to Connect-MgGraph, the Azure Resource Manager
    audience cached for Invoke-OERArmRequest, and the Entra ID authority (STS) host -- is read from
    Get-OERCloudEndpoint, which is the single owner of that table. The cloud joins the tenant and the
    auth identity in the token cache key, so a cloud switch always re-acquires rather than reusing a
    token minted at the previous cloud's authority. Microsoft 365 GCC is a commercial-cloud tenant:
    it uses the worldwide endpoints and needs no cloud selection at all, which is to say GCC is
    'Global'. GCC High is 'USGov', DoD is 'USGovDoD', and only a 21Vianet tenant is 'China'.

    AzAuth's Get-AzToken exposes no authority parameter, so a non-Global cloud is selected by setting
    the AZURE_AUTHORITY_HOST process environment variable around the token calls and restoring the
    previous value afterwards; Azure.Identity bakes that value into the credential it constructs.
    AzAuth also caches its credential in a static field that is keyed on neither the tenant nor the
    authority, so a cloud switch additionally passes -Force, which is the only supported way to make
    AzAuth drop that cached credential and construct a new one at the new authority.

    .PARAMETER TenantId
    The Entra ID tenant GUID or verified domain. When omitted, the tenant of the current session is
    used; when there is no session, 'organizations' is used. A value naming a different tenant than
    the session inherits nothing else from it.

    .PARAMETER AuthMethod
    The credential type used by Get-AzToken: Interactive, DeviceCode, ManagedIdentity, ClientSecret,
    or ClientCertificate. When omitted (and -ClientId is also omitted), the credential of the current
    session is inherited; when there is no session, Interactive is used. An explicit value always
    overrides the session.

    .PARAMETER ClientId
    The application (client) ID for ClientSecret, ClientCertificate, or user-assigned ManagedIdentity.

    .PARAMETER ClientSecret
    A SecureString containing the application client secret used with the ClientSecret auth method.
    The plaintext is materialized into the Get-AzToken splat for the duration of the token calls,
    and this function's references to it are dropped in a finally block once they complete. Because
    a .NET string is immutable, that bounds the value's lifetime to the call and shortens its time
    on the managed heap; it does not scrub the plaintext from memory.

    .PARAMETER Certificate
    An X509Certificate2 used with the ClientCertificate auth method.

    .PARAMETER CertificatePath
    A path to a certificate file used with the ClientCertificate auth method when an in-memory
    certificate object is not supplied.

    .PARAMETER IncludeARM
    Also acquire an Azure Resource Manager token and cache it (as a SecureString) in the module auth
    state. Required before any Azure Resource Manager cmdlet (which routes through Invoke-OERArmRequest)
    is used in the session.

    .PARAMETER ClaimsChallenge
    The decoded JSON claims challenge from a 401 WWW-Authenticate header, forwarded to Get-AzToken
    as -Claim to perform an interactive ACRS step-up.

    .PARAMETER ForceRefresh
    Bypass the cached-token idempotency check and acquire a fresh token.

    .PARAMETER Environment
    The sovereign cloud to authenticate against and request endpoints for: 'Global' (the worldwide
    commercial cloud, which is also what Microsoft 365 GCC runs on), 'USGov' (GCC High), 'USGovDoD'
    (DoD) or 'China' (21Vianet). When omitted, the cloud of the current session for the same tenant
    is inherited; when there is no such session, 'Global' is used. The value joins the tenant and the
    auth identity in the token cache key, so naming a different cloud always re-acquires.

    .EXAMPLE
    Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod Interactive

    .EXAMPLE
    $Secret = ConvertTo-SecureString 'mySecret' -AsPlainText -Force
    Initialize-OERAuth -TenantId $TenantId -AuthMethod ClientSecret -ClientId $AppId -ClientSecret $Secret

    .EXAMPLE
    Initialize-OERAuth -TenantId $TenantId -AuthMethod ClientCertificate -ClientId $AppId -CertificatePath $Pfx -IncludeARM
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [ValidateSet('Interactive', 'DeviceCode', 'ManagedIdentity', 'ClientSecret', 'ClientCertificate')]
        [string]$AuthMethod,
        [string]$ClientId,
        [securestring]$ClientSecret,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$CertificatePath,
        [switch]$IncludeARM,
        [string]$ClaimsChallenge,
        [switch]$ForceRefresh,
        # SEC: deliberately NO '= Global' default, for exactly the reason spelled out on
        # -AuthMethod below. A parameter default makes every predicate that reads this value compare
        # a cached session against the DEFAULT instead of against what the caller asked for; that was
        # a real defect on -AuthMethod (an app-only session pushed into a browser prompt) and it
        # would be the same defect here (a session established in a sovereign cloud re-derived as
        # 'Global' by any cmdlet that does not name a cloud, which is all of them). Empty means
        # 'inherit'; the three-way derivation below turns that into a value.
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment
    )

    # Public first-party client 'Microsoft Graph Command Line Tools'. It is preauthorized for
    # delegated Microsoft Graph scopes, so interactive and device-code sign-in can request the
    # Graph scopes below without an app registration. The AzAuth default client (Azure CLI) is
    # NOT preauthorized for these Graph scopes and fails with AADSTS65002. App-registration flows
    # (ClientSecret/ClientCertificate) use the caller's own ClientId instead.
    [string]$DefaultGraphClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
    [string[]]$GraphScopes = @(
        'Group.ReadWrite.All'
        'RoleManagement.ReadWrite.Directory'
        'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
        'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
        'RoleManagementPolicy.ReadWrite.AzureADGroup'
        'AdministrativeUnit.ReadWrite.All'
        'EntitlementManagement.ReadWrite.All'
        'AccessReview.ReadWrite.All'
        'Directory.Read.All'
        'User.Read'
    )

    # Derive the effective request target ONCE, before any predicate reads it. Comparing a cached
    # session against a PARAMETER DEFAULT rather than against what the caller actually asked for is
    # the shape of both defects this block closes.
    #
    # A cached session is a source of defaults only when the request targets ITS tenant: an access
    # token is issued for exactly one tenant and one principal, the same invariant $ArmCached and
    # $ArmIdentityUnchanged encode below. An explicitly requested DIFFERENT tenant inherits nothing
    # and behaves exactly as it did before this block existed.
    #
    # Emptiness, not $PSBoundParameters.ContainsKey: Connect-OER passes TenantId unconditionally and
    # that value is '' when neither -TenantId nor -TenantAlias was supplied, so ContainsKey would
    # read an absent tenant as a deliberate selection.
    [bool]$SessionUsable = [bool]$script:_OERAuthState -and
        (-not $TenantId -or $script:_OERAuthState.TenantId -eq $TenantId)

    # SEC: without the session term, omitting -TenantId stamped the state 'organizations' over a
    # real tenant id and called Get-AzToken with no -Tenant, so the cached label stopped describing
    # the token beneath it. Keep this term independently deletable so its guard test stays
    # mutation-provable.
    [string]$EffectiveTenant = if ($TenantId) {
        $TenantId
    }
    elseif ($SessionUsable -and $script:_OERAuthState.TenantId) {
        [string]$script:_OERAuthState.TenantId
    }
    else {
        'organizations'
    }

    # SEC: AuthMethod and ClientId are inherited as a PAIR, and only when the caller stated no
    # -AuthMethod and either no -ClientId or the SAME -ClientId as the cached session. Inheriting a
    # client id into a deliberately chosen credential would silently change which application the
    # sign-in runs as; inheriting a method WITHOUT its client id would re-acquire a user-assigned
    # managed identity as the system-assigned one -- a different principal, and the exact failure
    # both wrapper retries already forward ClientId to avoid. A -ClientId naming a DIFFERENT
    # application than the cached one must still force re-authentication as that application, not
    # silently continue under the cached one -- that was the one-way gap in the old $PassiveReuse
    # early-return, which ignored ClientId entirely.
    [bool]$InheritIdentity = $SessionUsable -and -not $AuthMethod -and
        (-not $ClientId -or $ClientId -eq $script:_OERAuthState.ClientId)

    # SEC: -AuthMethod used to declare '= Interactive', so the predicates below compared the cached
    # method against that DEFAULT whenever the caller omitted it. None of the 22 ARM cmdlets pass
    # -AuthMethod, so a non-interactive session calling any of them fell through to
    # 'Get-AzToken -Interactive': an unattended run stopped at a browser prompt, and an attended one
    # silently continued as a different principal. An explicit -AuthMethod still wins.
    [string]$EffectiveMethod = if ($AuthMethod) {
        $AuthMethod
    }
    elseif ($InheritIdentity -and $script:_OERAuthState.AuthMethod) {
        [string]$script:_OERAuthState.AuthMethod
    }
    else {
        'Interactive'
    }

    [string]$EffectiveClientId = if ($ClientId) {
        $ClientId
    }
    elseif ($InheritIdentity -and $script:_OERAuthState.ClientId) {
        [string]$script:_OERAuthState.ClientId
    }
    else {
        ''
    }

    # SEC: the cloud is a property of the TENANT, not of the credential, so it inherits on
    # $SessionUsable (the tenant term) rather than on $InheritIdentity. Signing in to the SAME
    # sovereign tenant with a different credential must stay in that tenant's cloud; naming a
    # DIFFERENT tenant inherits nothing, exactly as $EffectiveTenant does.
    [string]$EffectiveEnvironment = if ($Environment) {
        $Environment
    }
    elseif ($SessionUsable -and $script:_OERAuthState.Environment) {
        [string]$script:_OERAuthState.Environment
    }
    else {
        'Global'
    }

    # Get-OERCloudEndpoint is the single owner of the cloud-to-endpoint table. Never write a cloud
    # URL literal here: the two resource strings below are the ones this file used to hardcode, and
    # the 'Global' row reproduces them byte for byte.
    $Endpoint = Get-OERCloudEndpoint -Environment $EffectiveEnvironment
    [string]$GraphResource = $Endpoint.GraphResource
    [string]$ArmResource   = $Endpoint.ArmResource

    # AzAuth caches its credential in a STATIC field and reuses it whenever the credential type and
    # client id match -- neither the tenant nor the authority is part of that reuse condition. A
    # credential already constructed at the previous cloud's authority would therefore be reused and
    # AZURE_AUTHORITY_HOST would have no effect at all, since Azure.Identity bakes the authority in
    # per instance at construction time. -Force is the only door: GetAzToken.BeginProcessing calls
    # TokenManager.ClearCredential() if and only if -Force is present, and TokenManager is internal
    # and lives in a private AssemblyLoadContext, so nothing else can reach it.
    #
    # Seeded with the PUBLIC authority rather than $null so a session that only ever uses 'Global'
    # never gains a -Force it did not have before this parameter existed.
    if (-not $script:_OERLastAuthorityHost) {
        $script:_OERLastAuthorityHost = (Get-OERCloudEndpoint -Environment 'Global').AuthorityHost
    }
    [string]$EffectiveAuthorityHost = $Endpoint.AuthorityHost

    $FiveMinutesFromNow = [DateTime]::UtcNow.AddMinutes(5)

    # I2: cache is only valid when tenant AND auth identity (AuthMethod + ClientId) all match.
    #
    # This also replaces the former $PassiveReuse early-return, which existed only to let a caller
    # that named no credential reuse a session established under a different one. That is now true by
    # construction: when the caller states no -AuthMethod and either no -ClientId or the cached one,
    # $EffectiveMethod and $EffectiveClientId ARE the cached values, so both terms below hold. Its ARM
    # requirement is $ArmCached and its tenant term is $EffectiveTenant.
    #
    # One case is deliberately NOT carried over: $PassiveReuse ignored -ClientId entirely, so a caller
    # naming a DIFFERENT application's client id also reused the cached session. That is the same
    # silent wrong-identity family this predicate exists to close, so a differing -ClientId now forces
    # re-authentication. Do not reintroduce a second early-return here -- two overlapping cache
    # predicates drift.
    #
    # SEC: the Environment term is the cloud half of the same invariant. A token is minted by ONE
    # cloud's authority for ONE cloud's resource, so a cached Global token can never serve a USGov
    # request -- reusing it is the same defect class as the audit's only Critical (an ARM token
    # surviving a tenant switch). A state that carries no Environment at all does not match any
    # cloud and re-acquires, which is the safe direction. Keep this term on its own line and
    # independently deletable, like every other term here, so its guard test stays mutation-provable.
    [bool]$GraphCached = $script:_OERAuthState -and
        $script:_OERAuthState.AuthMethod -eq $EffectiveMethod -and
        $script:_OERAuthState.ClientId   -eq $EffectiveClientId -and
        $script:_OERAuthState.TenantId   -eq $EffectiveTenant -and
        $script:_OERAuthState.Environment -eq $EffectiveEnvironment -and
        -not $ClaimsChallenge -and -not $ForceRefresh -and
        $script:_OERAuthState.GraphTokenExpiry -gt $FiveMinutesFromNow

    # SEC: the ARM predicate carries the SAME tenant and identity terms as the Graph one, and for
    # the same reason -- an access token is issued for exactly one tenant and one principal. Without
    # them a tenant switch kept the previous tenant's ARM token while $script:_OERAuthState.TenantId
    # reported the new tenant, so every ARM read returned the PREVIOUS customer's resources under the
    # new customer's label, and a write reached by friendly name landed in the previous customer's
    # tenant with no error.
    #
    # The '-not $ForceRefresh' term is a SEPARATE defect and is equally load-bearing: an ARM 401 is
    # not necessarily an expiry (revocation, CAE, key rotation, or a stale token from another
    # tenant), so without it Invoke-OERArmRequest's forced-refresh retry re-sent the identical
    # rejected bearer and guaranteed a second 401. Do not fold these terms into a shared variable
    # with $GraphCached: each one must stay independently deletable so its guard test can be
    # mutation-proved.
    [bool]$ArmCached = (-not $IncludeARM) -or (
        $script:_OERAuthState -and
        $script:_OERAuthState.TenantId   -eq $EffectiveTenant -and
        $script:_OERAuthState.AuthMethod -eq $EffectiveMethod -and
        $script:_OERAuthState.ClientId   -eq $EffectiveClientId -and
        $script:_OERAuthState.Environment -eq $EffectiveEnvironment -and
        -not $ForceRefresh -and
        $script:_OERAuthState.ArmToken -and
        $script:_OERAuthState.ArmTokenExpiry -and
        $script:_OERAuthState.ArmTokenExpiry -gt $FiveMinutesFromNow)

    # Captured BEFORE the state is rebuilt below: does the state being replaced belong to the same
    # tenant and principal we are now authenticating as? This gates the ARM carry-forward at the
    # rebuild and is the half of the tenant-isolation fix that $ArmCached cannot cover, because a
    # tenant switch made WITHOUT -IncludeARM short-circuits $ArmCached to $true and skips it.
    #
    # The Environment term carries here for the same reason it carries on $ArmCached: an ARM token
    # minted at one cloud's authority for that cloud's ARM audience is worthless -- and misleading --
    # under another cloud's label, and a cloud switch made WITHOUT -IncludeARM short-circuits
    # $ArmCached to $true, so only this guard can drop it.
    [bool]$ArmIdentityUnchanged = $script:_OERAuthState -and
        $script:_OERAuthState.TenantId   -eq $EffectiveTenant -and
        $script:_OERAuthState.AuthMethod -eq $EffectiveMethod -and
        $script:_OERAuthState.ClientId   -eq $EffectiveClientId -and
        $script:_OERAuthState.Environment -eq $EffectiveEnvironment

    if ($GraphCached -and $ArmCached) {
        Write-Verbose "[Initialize-OERAuth] Returning cached auth state for tenant '$EffectiveTenant'."
        return
    }

    # SEC: an INHERITED app-only identity cannot mint a token at all. The client-credentials flow
    # issues no refresh token and a token is minted for exactly one resource, so the cached Graph
    # token can never be traded for an ARM one -- and this module deliberately never stores the
    # secret or certificate to replay it. Fixing the derivation above therefore cannot make this
    # case succeed; it makes it fail LOUDLY instead of opening a browser as a different principal.
    # Same policy, third site: Invoke-OERGraphRequest raises AppOnlyClaimsChallengeUnsatisfiable and
    # AppOnlyTokenRefreshUnsatisfiable, Invoke-OERArmRequest raises AppOnlyTokenRefreshUnsatisfiable.
    #
    # Two placement constraints, both load-bearing:
    #   - BELOW the cached return, so a session that needs no new token is never rejected.
    #   - ABOVE the state rebuild, so the caller keeps a session whose TenantId still names the real
    #     tenant instead of being stamped 'organizations'.
    # Gated on $InheritIdentity: an EXPLICIT -AuthMethod ClientSecret with no secret is a caller
    # mistake and keeps its own, more specific MissingClientSecret error below.
    if ($InheritIdentity -and ($EffectiveMethod -in 'ClientSecret', 'ClientCertificate') -and
        -not $ClientSecret -and -not $Certificate -and -not $CertificatePath) {
        Write-CmdletError `
            -Message ([System.Exception]::new(
                "The cached session for tenant '$EffectiveTenant' is app-only ($EffectiveMethod) and a new " +
                "access token is required$(if ($IncludeARM) { ' for Azure Resource Manager' }), but the module " +
                "does not cache client secrets or certificates and cannot acquire one. Re-run Connect-OER with " +
                "the client secret or certificate" +
                "$(if ($IncludeARM) { ' and -IncludeARM' }) to establish a session that covers this call.")) `
            -ErrorId 'AppOnlySessionCredentialUnavailable' `
            -Category AuthenticationError `
            -TargetObject $EffectiveTenant `
            -Cmdlet $PSCmdlet `
            -Terminating
    }

    # I3: validate required credential material before attempting token acquisition.
    switch ($EffectiveMethod) {
        'ClientSecret' {
            if (-not $EffectiveClientId -or -not $ClientSecret) {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "AuthMethod 'ClientSecret' requires both -ClientId and -ClientSecret. " +
                        "$(if (-not $EffectiveClientId) { '-ClientId is missing. ' })" +
                        "$(if (-not $ClientSecret) { '-ClientSecret is missing.' })")) `
                    -ErrorId 'MissingClientSecret' `
                    -Category InvalidArgument `
                    -TargetObject $EffectiveMethod `
                    -Cmdlet $PSCmdlet `
                    -Terminating
            }
        }
        'ClientCertificate' {
            if (-not $EffectiveClientId -or (-not $Certificate -and -not $CertificatePath)) {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "AuthMethod 'ClientCertificate' requires -ClientId and either -Certificate or -CertificatePath. " +
                        "$(if (-not $EffectiveClientId) { '-ClientId is missing. ' })" +
                        "$(if (-not $Certificate -and -not $CertificatePath) { 'Neither -Certificate nor -CertificatePath was supplied.' })")) `
                    -ErrorId 'MissingClientCertificate' `
                    -Category InvalidArgument `
                    -TargetObject $EffectiveMethod `
                    -Cmdlet $PSCmdlet `
                    -Terminating
            }
        }
    }

    # -- The ONLY two Get-AzToken call sites in this module route through here --
    #
    # WHY THIS EXISTS. On the device-code flow the sign-in instruction ("To sign in, use a web
    # browser to open the page https://.../device and enter the code XXXXXXXXX to authenticate.")
    # is not a warning at all: it is the primary interaction, and the operator cannot complete the
    # sign-in without acting on it. AzAuth emits it on the WARNING stream --
    # PipeHow.AzAuth.TokenManager's device-code callback pushes Azure.Identity's DeviceCodeInfo
    # .Message into a BlockingCollection[string] and PipeHow.AzAuth.GetAzToken.EndProcessing drains
    # that queue through Cmdlet::WriteWarning (confirmed by IL disassembly at IL_0483 of
    # EndProcessing). That is AzAuth's code and cannot be changed from here, but how this module
    # CONSUMES it can be. Anything running under -WarningAction SilentlyContinue or
    # $WarningPreference = 'SilentlyContinue' -- an automation host, a wrapper script, a caller who
    # silenced warnings for an unrelated reason -- never saw the code at all, and the sign-in then
    # looked like a hang until it timed out. That is the defect; the misleading "WARNING:" prefix on
    # an instruction is the second half of it.
    #
    # 3>&1 merges the warning records into the success stream, and PowerShell streams a pipeline
    # element-by-element as it is produced, so the code is re-emitted on the INFORMATION stream
    # WHILE Get-AzToken is still blocking on the sign-in. A message printed after the flow completed
    # would be useless -- the code has expired by then. Measured: the information record is written
    # ~300 ms before the token call returns in a fixture that warns and then sleeps.
    #
    # -WarningAction Continue IS LOAD-BEARING, not decoration. A redirection can only move a record
    # that was actually produced, and PowerShell drops a WarningRecord AT SOURCE when the effective
    # preference is SilentlyContinue -- so under the very automation host this whole fix exists for,
    # 3>&1 merged nothing and the operator still saw no code. Measured at language level:
    # $WarningPreference = 'SilentlyContinue'; @(Write-Warning 'x' 3>&1) yields COUNT 0, and adding
    # -WarningAction Continue restores the record; measured again through this module against a
    # silenced global preference. Get-AzToken is a compiled cmdlet (PipeHow.AzAuth.GetAzToken), so
    # WarningAction is a common parameter present in all ELEVEN of its parameter sets -- verified by
    # reflection over Get-Command Get-AzToken, not assumed -- and it cannot collide with the splat:
    # $TokenParams below never carries a WarningAction key. It is passed at the CALL, not set as a
    # preference variable in this function, so its reach is exactly one command.
    #
    # EVERY AzAuth warning raised on this path is downgraded to information, not only the
    # device-code instruction, and that is a deliberate trade rather than an oversight. The
    # instruction cannot be told apart from an unrelated warning without matching AzAuth's English
    # sentence, and such a match would fail CLOSED -- straight back to an invisible code -- the
    # first time AzAuth reworded its own text. The trade is narrow and lossless: this path is
    # reached only for -AuthMethod DeviceCode, only around the two token acquisitions, and the
    # record is re-emitted verbatim on a stream a silenced host still shows. An unrelated AzAuth
    # warning is therefore RE-LABELLED, never suppressed, and every other credential type keeps its
    # warnings on the warning stream untouched.
    #
    # -InformationAction Continue, not a bare Write-Information: the point is that the instruction
    # survives a silenced host. Write-Host would do the same and is banned by PSAvoidUsingWriteHost.
    #
    # DEVICE CODE ONLY. Every other credential type still calls Get-AzToken exactly as it always
    # did, with no pipeline in between -- the public, non-device-code path staying byte-identical is
    # the invariant the sovereign-cloud work protects, and the -DeviceCodeFlow switch keeps it
    # provable. The AzToken object itself is passed through unchanged (a single object, so the
    # pipeline neither wraps nor unrolls it), and a terminating Get-AzToken failure still propagates
    # out of the pipeline into the caller's try/catch -- a redirection does not swallow a throw.
    #
    # BOTH call sites, Graph and ARM. On the device-code path the ARM acquisition is expected to
    # raise a device code of its own rather than reuse the Graph sign-in: the Graph call passes a
    # client id (the caller's, or $DefaultGraphClientId) and the ARM call passes none, and AzAuth
    # reuses its process-wide credential only for the same credential type AND the same client id.
    # Measured offline, with the network blocked: a device-code Graph call followed by a device-code
    # ARM call for the same tenant built a NEW credential instance for the ARM call, under
    # Azure.Identity's default public client. Inferred from the decompiled Azure.Identity, not
    # executed: that new instance holds neither the Graph sign-in's authentication record nor its
    # in-memory token cache, so it cannot complete silently. That the operator is then shown a second
    # device code follows from that inference and has not yet been observed live. The ARM acquisition
    # is also reached with Force still on the splat under -ForceRefresh, and on its own by an
    # -IncludeARM call made when only the Graph token was cached. Every one of these shapes can raise
    # a real device code, and an invisible one there fails exactly the same way.
    function Invoke-AzTokenCall {
        param(
            [hashtable]$TokenParameter,
            [switch]$DeviceCodeFlow
        )
        if (-not $DeviceCodeFlow) {
            return Get-AzToken @TokenParameter
        }
        Get-AzToken @TokenParameter -WarningAction Continue 3>&1 | ForEach-Object {
            if ($PSItem -is [System.Management.Automation.WarningRecord]) {
                Write-Information -MessageData $PSItem.Message -InformationAction Continue
            }
            else {
                $PSItem
            }
        }
    }

    # Build the common Get-AzToken splat for the selected credential.
    $TokenParams = @{ ErrorAction = 'Stop' }
    if ($EffectiveTenant -ne 'organizations') { $TokenParams.Tenant = $EffectiveTenant }
    if ($ClaimsChallenge) { $TokenParams.Claim = $ClaimsChallenge }
    # ORed, not overwritten: -ForceRefresh keeps its own reason for forcing, and a cloud switch adds
    # a second one. See the $script:_OERLastAuthorityHost comment above for why AzAuth's static
    # credential cache leaves -Force as the only way to move the authority.
    if ($ForceRefresh -or $EffectiveAuthorityHost -ne $script:_OERLastAuthorityHost) {
        $TokenParams.Force = $true
    }

    # Captured OUTSIDE the try so the finally below always has a real previous value to restore,
    # even if the very first statement inside the try were to fail. Deliberately NOT [string]-typed:
    # GetEnvironmentVariable returns $null -- not '' -- for an unset variable, and the finally
    # distinguishes the two to decide between deleting and re-writing. A [string] cast here would
    # collapse "absent" into "empty" before that decision could be made.
    $PreviousAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
    [bool]$AuthorityHostOverridden = $false

    try {
        # AzAuth's Get-AzToken has no -Environment, -Authority or -Instance parameter in any of its
        # eleven parameter sets, so the authority is moved through the process environment variable
        # Azure.Identity reads when it constructs the credential. Set ONCE around both token calls:
        # both are for the same tenant, identity and cloud, and one set with one restore in the
        # finally that already guards this whole block is the only shape where every terminating
        # path -- GraphTokenAcquisitionFailed, GraphConnectFailed, ArmTokenAcquisitionFailed -- is
        # covered by construction rather than by three separate hand-written restores.
        #
        # 'Global' writes NOTHING. Connect-MgGraph and Azure.Identity both default to the public
        # cloud already, so writing the public authority would only be a no-op with a side effect --
        # and the public path staying byte-identical is provable only if there is no write to prove
        # away. It also means an operator who has deliberately set AZURE_AUTHORITY_HOST for the
        # public cloud keeps their setting.
        if ($EffectiveEnvironment -ne 'Global') {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $EffectiveAuthorityHost)
            $AuthorityHostOverridden = $true
        }
        elseif ($PreviousAuthorityHost -and
            $PreviousAuthorityHost.TrimEnd('/') -ne $Endpoint.AuthorityHost.TrimEnd('/')) {
            # Global still writes NOTHING -- the byte-identical public path is the invariant this
            # whole sprint protects, and an operator who set this variable set it deliberately. But
            # Azure.Identity WILL follow it, so this sign-in goes to that authority instead of the
            # commercial one, and the STS error that follows names the TENANT and never the
            # authority. Explaining it is the only thing this branch does. Not terminating: a tenant
            # lives in exactly one cloud, so this can never mint a wrong-cloud token -- it fails
            # loudly on its own.
            Write-Warning (
                "AZURE_AUTHORITY_HOST is set to '$PreviousAuthorityHost' in this process, which is " +
                "not the commercial-cloud authority '$($Endpoint.AuthorityHost)'. Microsoft Entra ID " +
                "sign-in follows that variable, so this 'Global' sign-in will be sent to that " +
                "authority instead. Omnicit.EntraRBAC does not change the variable on the Global " +
                "cloud. If this is not what you intended, clear it with " +
                "Remove-Item Env:AZURE_AUTHORITY_HOST and sign in again; if you meant to target a " +
                "sovereign cloud, use Connect-OER -Environment instead.")
        }

        # SEC: a same-session tenant switch with a client secret does not reach the new tenant unless
        # AzAuth rebuilds its credential, and nothing the caller sees says so. AzAuth keeps ONE
        # credential for the whole process and, for a client secret, reuses it whenever the credential
        # already in its static field is a client-secret credential for the same client id -- the
        # tenant is not part of that test, and Azure.Identity bakes the tenant into the credential when
        # it constructs it. Measured offline, with the network blocked: a second Get-AzToken for the
        # same client id and a different tenant, without -Force, received the SAME credential instance,
        # still built for the first tenant -- for a GUID and for a domain alike. What happened next
        # depended on one process switch:
        #   - By default Azure.Identity refused before sending anything: 'The current credential is not
        #     configured to acquire tokens for tenant <new>', in 0.01 s, with no request made. This
        #     function would surface that as GraphTokenAcquisitionFailed, and the text points at
        #     Azure.Identity's multi-tenant guidance -- a credential option AzAuth never sets -- and
        #     never at the -Force that fixes it.
        #   - With AZURE_IDENTITY_DISABLE_MULTITENANTAUTH=true the same call sent its token request to
        #     the PREVIOUS tenant, silently; the only trace was an Azure.Identity diagnostic event.
        #   - With -Force a NEW credential was built for the new tenant, and the request went there.
        # A PREDICTION made here, before the call, rather than an interpretation of the error after it:
        # the refusal shares its error id and exception type with every other client secret failure,
        # so only Azure.Identity's English sentence could tell the two apart.
        #
        # -ceq on the client id: AzAuth's reuse test is a plain ordinal string inequality (decompiled),
        # so a client id that differs only in letter case gets a NEW credential built for the new
        # tenant, and warning about it would be false. -ne on the tenant: the decompiled Azure.Identity
        # tenant resolver compares the requested tenant with the credential's ignoring case, both where
        # it refuses and where it redirects, so a case-only difference is the same tenant to it.
        #
        # ClientSecret ONLY, on both sides of the comparison. The advice here is -Force, and for the
        # other types it would be false: a device-code credential never holds a tenant -- every
        # device-code request measured went to 'organizations' whatever -Tenant said, with -Force and
        # without -- and a managed identity request was byte-identical for any tenant, with -Force and
        # without. Client certificate and interactive credentials are rebuilt on every call
        # (decompiled), so no earlier tenant survives into them. And when the record names any other
        # type, the credential AzAuth last built is not a client-secret credential, so the next client
        # secret request replaces it. The post-call check after the Graph token observes what
        # this one cannot predict.
        #
        # Every term on its own line and independently deletable, so each stays mutation-provable.
        [bool]$ClientSecretTenantSwitchWithoutForce = $EffectiveMethod -eq 'ClientSecret' -and
            $script:_OERLastTokenRequest -and
            $script:_OERLastTokenRequest.AuthMethod -eq 'ClientSecret' -and
            $script:_OERLastTokenRequest.ClientId -ceq $EffectiveClientId -and
            $script:_OERLastTokenRequest.TenantId -ne $EffectiveTenant -and
            -not $TokenParams.ContainsKey('Force')

        if ($ClientSecretTenantSwitchWithoutForce) {
            [string]$CredentialBuiltForTenant = $script:_OERLastTokenRequest.TenantId
            Write-Warning (
                "This client secret sign-in for application '$EffectiveClientId' names tenant " +
                "'$EffectiveTenant', but the credential AzAuth holds for that application in this " +
                "PowerShell session was built for tenant '$CredentialBuiltForTenant'. AzAuth reuses that " +
                "credential for the same application until it is told to rebuild it, so this sign-in does " +
                "not reach '$EffectiveTenant': by default it fails with 'The current credential is not " +
                "configured to acquire tokens for tenant', and where multi-tenant authentication is " +
                "disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from " +
                "'$CredentialBuiltForTenant' instead. Run Connect-OER again with -Force to rebuild the " +
                "credential for '$EffectiveTenant'. Disconnect-OER does not clear it.")
        }

        # The module's own record of the token request that last made AzAuth BUILD its credential, which
        # the prediction above reads -- and so, for a client secret, of the tenant the credential AzAuth
        # holds was built for. It is NOT the last request attempted. It moves only when this call makes
        # AzAuth build a new credential, and stays where it is when AzAuth will reuse the one it has:
        #   - A call of the same credential type with the same client id and no Force REUSES the
        #     credential. Measured: a second client secret call for the same client id and another
        #     tenant, without -Force, received the SAME credential instance, still built for the first
        #     tenant. Such a call must not move the record, whether AzAuth then answers it or refuses
        #     it: a refused switch leaves the credential built for the old tenant in place, so recording
        #     the refused tenant made the next sign-in back to the old tenant -- which works -- warn.
        #   - Force builds a new credential for the requested tenant (measured, client secret). So does
        #     a different client id: measured on the device-code path, and the client secret path runs
        #     the same ordinal client id test in the decompiled AzAuth, which is why the comparison is
        #     -cne. So does a different credential type (decompiled: the reuse test checks the stored
        #     credential's type). Each of these moves the record.
        # The record's TenantId means something only for a client secret, the one type the prediction
        # reads it for. For every other type -- device code, managed identity, interactive, client
        # certificate -- the record exists so that a later client secret call sees the change of type.
        #
        # A tracker, not $script:_OERAuthState, since the state records neither of the two things that
        # decide what AzAuth reuses. AzAuth's credential outlives a FAILED call -- measured: every first
        # attempt in the offline runs failed and still left the credential it built for the next call to
        # reuse -- so a failed call that BUILDS a credential still moves the record, while the state is
        # written only after a Graph token was acquired. And the credential outlives Disconnect-OER,
        # which clears the state: it is process-wide (measured: a second runspace reused it, and removing
        # and re-importing AzAuth left it in place), Clear-AzTokenCache measurably does not clear it with
        # or without -Force, and only Get-AzToken -Force drops it. Disconnect-OER must therefore NOT
        # clear this tracker, exactly as it leaves $script:_OERLastAuthorityHost alone. Updated before
        # the call, AFTER the prediction above has read the record as it stood, for the same reason the
        # authority tracker below is recorded before the call. It is still only this module's view: a
        # Get-AzToken call made outside this module, or a reload of this module, is invisible to it.
        #
        # Every term on its own line and independently deletable, so each stays mutation-provable.
        [bool]$AzAuthBuildsNewCredential = -not $script:_OERLastTokenRequest -or
            $script:_OERLastTokenRequest.AuthMethod -ne $EffectiveMethod -or
            $script:_OERLastTokenRequest.ClientId -cne $EffectiveClientId -or
            $TokenParams.ContainsKey('Force')
        if ($AzAuthBuildsNewCredential) {
            $script:_OERLastTokenRequest = @{ AuthMethod = $EffectiveMethod; ClientId = $EffectiveClientId; TenantId = $EffectiveTenant }
        }

        # Recorded HERE -- before any credential can be constructed -- and deliberately NOT after a
        # successful acquisition. Get-AzToken constructs the credential and THEN requests the token,
        # so a sovereign attempt that fails (a cancelled prompt, a Conditional Access policy, a
        # network blip) still leaves AzAuth's static credential baked to the new authority while
        # nothing was written to $script:_OERAuthState. Recording on success would leave the tracker
        # naming the OLD authority, so the operator's next plain Global sign-in would compare equal,
        # skip -Force, reuse that sovereign-baked credential, and fail with an AADSTS error naming
        # the tenant and never the authority -- poisoning every later Global sign-in in the process
        # until a -ForceRefresh or a restart. Recording the ATTEMPT costs at most one redundant
        # -Force, which only rebuilds a credential.
        $script:_OERLastAuthorityHost = $EffectiveAuthorityHost

        switch ($EffectiveMethod) {
            'Interactive'      { $TokenParams.Interactive = $true }
            'DeviceCode'       { $TokenParams.DeviceCode = $true }
            'ManagedIdentity'  { $TokenParams.ManagedIdentity = $true; if ($EffectiveClientId) { $TokenParams.ClientId = $EffectiveClientId } }
            'ClientSecret'     {
                # C1: materialize the plaintext secret only at the call boundary; never store the raw string.
                $TokenParams.ClientId     = $EffectiveClientId
                $TokenParams.ClientSecret = [System.Net.NetworkCredential]::new('', $ClientSecret).Password
            }
            'ClientCertificate' {
                $TokenParams.ClientId = $EffectiveClientId
                if ($Certificate) { $TokenParams.ClientCertificate = $Certificate }
                else              { $TokenParams.ClientCertificatePath = $CertificatePath }
            }
        }

        # -- Graph token --
        if (-not $GraphCached) {
            # M6: Clone() is a shallow clone - only top-level keys are mutated per-resource call,
            #     so nested objects (e.g. certificate) are safely shared without duplication.
            $GraphParams = $TokenParams.Clone()
            $GraphParams.Resource = $GraphResource
            # Delegated flows can request granular scopes; app-only flows use the resource default.
            # For delegated flows, request Graph via the preauthorized public client (or the caller's
            # own ClientId when supplied) so consent for the Graph scopes can be granted interactively.
            if ($EffectiveMethod -in 'Interactive', 'DeviceCode') {
                $GraphParams.Scope = $GraphScopes
                $GraphParams.ClientId = if ($EffectiveClientId) { $EffectiveClientId } else { $DefaultGraphClientId }
            }

            $GraphToken = try {
                Invoke-AzTokenCall -TokenParameter $GraphParams -DeviceCodeFlow:($EffectiveMethod -eq 'DeviceCode')
            } catch {
                # Security hygiene, uniform with the Graph and ARM transport wrappers: scrub first, then
                # report. A failed ClientSecret token call binds the plaintext secret into the request
                # this record describes.
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError `
                    -Message ([System.Exception]::new("Failed to acquire a Microsoft Graph token: $($PSItem.Exception.Message)")) `
                    -InnerException $PSItem.Exception `
                    -ErrorId 'GraphTokenAcquisitionFailed' `
                    -Category AuthenticationError `
                    -TargetObject $EffectiveTenant `
                    -Cmdlet $PSCmdlet `
                    -Terminating
            }

            # SEC: what the token was GRANTED for, not what the caller ASKED for. AzAuth's AzToken
            # exposes the tenant the token was actually issued for -- verified by reflection over
            # PipeHow.AzAuth.AzToken: Token, ExpiresOn, Identity, TenantId, Scopes, Claims -- and
            # this module consumed Identity and ExpiresOn while discarding TenantId. The cached
            # label could therefore stop describing the token beneath it, which is the same defect
            # the $EffectiveTenant comment above closes for a different cause and the same family as
            # the audit's only Critical (an ARM token surviving a tenant switch). A live run proved
            # it reachable, not theoretical: three device-code sign-ins named a tenant that does not
            # exist, the operator completed the tenant-independent verification page with a real
            # account, and all three returned a working session.
            #
            # Compared ONLY when BOTH values are canonical GUIDs, and that restriction is the whole
            # difficulty here. $EffectiveTenant is very often a verified DOMAIN
            # ('contoso.onmicrosoft.com') while the granted value is a GUID, so an unconditional
            # string comparison would reject almost every real sign-in. Test-OERGuid is the module's
            # single GUID predicate -- never re-implement its regex -- and it is also what excludes
            # 'organizations' and the empty string structurally, since neither is a GUID; a separate
            # term for either would be one no input could falsify, and an unfalsifiable term cannot
            # be mutation-proved. When the request named a domain the mismatch is not detectable
            # from the token alone, so nothing is guessed: TokenTenantId below records the granted
            # value and lets it speak for itself. -ne on strings is case-insensitive in PowerShell,
            # so a GUID typed in upper case still compares equal to the lower-case one Entra returns.
            #
            # Placement, on the same two-sided reasoning the app-only check above spells out:
            #   - BELOW the cached return, so a session that needs no new token is never rejected.
            #   - ABOVE both Connect-MgGraph and the $script:_OERAuthState rebuild, so a refused
            #     token is never wired into the Graph SDK session and never leaves a half-built
            #     state behind. The previous session, if any, survives untouched and still describes
            #     its own token.
            #
            # NOT [string]-typed: a cast collapses "AzAuth returned no tenant at all" into the empty
            # string, and TokenTenantId is an evidence field -- an absent value must stay absent
            # rather than read as a tenant named ''.
            $GrantedTenant = $GraphToken.TenantId
            if ((Test-OERGuid -Value $EffectiveTenant) -and (Test-OERGuid -Value $GrantedTenant) -and
                $GrantedTenant -ne $EffectiveTenant) {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "The Microsoft Graph token was issued for tenant '$GrantedTenant', not for the " +
                        "requested tenant '$EffectiveTenant'. Omnicit.EntraRBAC refuses a session whose " +
                        "cached tenant does not describe the token beneath it: every later call would act " +
                        "on '$GrantedTenant' while reporting '$EffectiveTenant'. Sign in again with an " +
                        "account that belongs to '$EffectiveTenant'.")) `
                    -ErrorId 'TenantMismatch' `
                    -Category AuthenticationError `
                    -TargetObject $EffectiveTenant `
                    -Cmdlet $PSCmdlet `
                    -Terminating
            }

            # SEC: a tenant switch that did not take effect, observed rather than predicted. Evaluated
            # HERE -- after the TenantMismatch guard, so a refused token never warns, and before the
            # tracker write that follows the state rebuild below, while $script:_OERLastIssuedSession
            # still describes the last session established in this PowerShell process. Deliberately
            # that tracker and not $script:_OERAuthState: Disconnect-OER clears the state, and
            # disconnecting before connecting to the next customer is the most natural way to switch,
            # so a check that read the state went silent on exactly that switch. The tracker survives
            # Disconnect-OER, for the reasons given where it is written.
            #
            # It compares GRANTED tenants, since for a request named by domain that is the only signal
            # there is: TenantMismatch above cannot compare a domain with the GUID a token carries.
            # Measured offline, with the network blocked: every device-code request went to
            # 'organizations' whatever -Tenant said, -Force included; a managed identity request was
            # byte-identical for any tenant; and a client secret credential reused under
            # AZURE_IDENTITY_DISABLE_MULTITENANTAUTH sent its token request to the PREVIOUS tenant.
            # Inferred, not executed, since no token can be issued offline: a device-code token is
            # therefore issued for the tenant of the account that signs in, and a managed identity token
            # for the identity's own tenant, so a switch made with either -- or with that reused client
            # secret credential -- comes back issued by the SAME tenant as before, under the new label,
            # which is the shape tested here. The DEVICE-CODE half of that inference is weakened, not
            # withdrawn: a RECORDED OBSERVATION from the 2026-09-15/16 live run has every device-code
            # sign-in that NAMED a tenant coming back issued by that tenant, which the offline spike
            # could not observe at all -- it measured the REQUEST going to 'organizations' and never got
            # as far as a token. An observation and not a rule, since which account completed each
            # device-code page was not recorded. The table, and the reading that reconciles it with the
            # earlier nonexistent-tenant finding -- the named tenant reaches the token when the account
            # can obtain one there, and falls back to the account's own tenant when it cannot, which is
            # exactly the shape this check exists to catch -- are in
            # docs/development/rationale.md#switching-tenants-in-one-process. That section governs; do
            # not grow a second copy of it here.
            #
            # A second inference used to sit here, and the live run split it in two. Still DECOMPILED,
            # from AzAuth and Azure.Identity: a device-code credential reused after a SUCCESSFUL sign-in
            # first attempts silent reacquisition for the REQUESTED tenant. CONTRADICTED BY MEASUREMENT,
            # 2026-09-16, twice independently and on a healthy connection -- through this module
            # (checklist 3.5) and against raw Get-AzToken outside it (4.2): there is no fall-back to a
            # new device code. The call never returns at all, printing no device code and raising no
            # error; in 3.5 the harness function returned $null, never reaching its own return
            # expression. -Force cured it every time it was used. So the reassurance once drawn from
            # that fall-back -- that such a switch may reach the new tenant after all, and this check
            # then stays silent by design -- does not follow, and is withdrawn.
            #
            # MEASURED live, 2026-09-15/16, against real tokens, where this was recorded as decompiled
            # only: AzToken.TenantId carries the acquired token's own tid claim. Checklist 4.1 (a first
            # device-code token), 4.2 (a switched one, taken with -Force) and 4.3a (a client secret
            # token) each decoded the token's own payload segment in memory and found the property equal
            # to tid and NOT an echo of the requested value, and 2.7b corroborates it a fourth time.
            # DECOMPILED and still NOT measured, since no live token exercised it: the property falls
            # back to echoing the REQUESTED tenant when the token carries no tid claim at all.
            #
            # A GUID request is excluded: TenantMismatch has already verified it and refuses a token
            # issued for any other tenant, and a session named by domain followed by the same tenant's
            # GUID is a correct sign-in that would otherwise warn. The previous TokenTenantId must
            # itself be a GUID, or an absent or unrecognisable tenant on both tokens would compare equal
            # and read as evidence.
            #
            # A request that names NO tenant is excluded as well: it asks for no particular tenant, so
            # there is no switch that could have failed to take effect. While this check read
            # $script:_OERAuthState that case could not arise -- a request with no tenant and a live
            # session inherits the session's tenant -- but through the tracker it can, right after
            # Disconnect-OER. It is NOT the previous-label 'organizations' shape below, where the
            # PREVIOUS session named no tenant and this one names a domain; that one still warns, on
            # purpose.
            #
            # TWO benign shapes also satisfy every term, and the message answers both with its sentence
            # "If '<new>' is a name of tenant '<granted>', this is expected":
            #   - two names for the same tenant, such as a verified domain and its onmicrosoft.com name;
            #   - a previous session that named no tenant, recorded as 'organizations', followed by a
            #     sign-in naming that same tenant's own domain: Connect-OER -Interactive (or
            #     -ManagedIdentity), then the same again with -TenantId <that tenant's domain>.
            # 'organizations' is deliberately NOT excluded as a previous label, since the failure this
            # check exists for has that very shape: a device-code sign-in naming no tenant, then
            # -TenantId <a customer's domain>, still issued by the operator's home tenant (the inferred
            # device-code behaviour above). Excluding it would silence exactly that. Telling a benign
            # shape from the failure needs the domain resolved to its tenant ID, which is a network call
            # on every sign-in -- which is also why this is a warning and not a refusal, by the
            # operator's decision.
            #
            # Still unchecked: the first sign-in in a process, which has no earlier session to compare
            # with, and the first sign-in after Omnicit.EntraRBAC is re-imported, which resets this
            # module's scope and the tracker with it.
            #
            # The message names Azure Resource Manager as well as Microsoft Graph, although the check
            # itself reads only the Graph token -- and for a module whose job is Azure RBAC, the ARM half
            # is the one that WRITES role assignments. MEASURED live, 2026-09-16, a managed identity
            # sign-in with -IncludeARM: on a switch that did not take effect the ARM token's granted
            # tenant equalled the Graph token's. The text is worded for the token a session of this shape
            # acquires, not for one it is known to hold: the warning fires whether or not the caller
            # passed -IncludeARM.
            #
            # It names ARM as AFFECTED and claims no MECHANISM tying the two tokens together, which it
            # must not: Graph and ARM share AzAuth's process-wide credential only where the client ids
            # match, and that is ManagedIdentity and ClientSecret alone. The comment above
            # Invoke-AzTokenCall carries the measurement -- the delegated Graph call passes a client id
            # and the ARM call passes none, so a DeviceCode Graph call followed by a DeviceCode ARM call
            # BUILT A NEW credential instance for the ARM one (measured offline) -- and the decompiled
            # TokenManager constructs a brand-new credential on every Interactive and ClientCertificate
            # call regardless. On those three the ARM acquisition is a SEPARATE sign-in whose tenant this
            # check never observes: it may reach the requested tenant, repeat the granted one, or land on
            # a third. So the ARM half's AGREEMENT with the Graph half is MEASURED for managed identity
            # and assumed nowhere else, and the message says only that the ARM calls are in this, not
            # that they cannot diverge from Graph.
            #
            # ONE warning and not two. This check runs BEFORE the ARM token is acquired below, so it
            # cannot read that token's tenant at all; and a second warning after the acquisition would
            # tell the same operator the same fact about the same credential a second time. The ARM half
            # is therefore carried by this message's wording rather than by a warning of its own.
            #
            # The limitation that stays: the ARM half's own tenant check is the GUID-only TenantMismatch
            # on the ARM token further below, the mirror of the Graph one above, and it is equally blind
            # to a request that names a domain. Resolving the named domain to its tenant ID through the
            # cloud authority's OpenID discovery document before the call -- proposed on this branch and
            # deliberately not built here, since it is a new network call on every sign-in -- would close
            # both at once.
            #
            # Every term on its own line and independently deletable, so each stays mutation-provable.
            $PreviousSession = $script:_OERLastIssuedSession
            [bool]$TenantSwitchNotTakenEffect = [bool]$PreviousSession -and
                $PreviousSession.TenantId -ne $EffectiveTenant -and
                $EffectiveTenant -ne 'organizations' -and
                -not (Test-OERGuid -Value $EffectiveTenant) -and
                (Test-OERGuid -Value $PreviousSession.TokenTenantId) -and
                $GrantedTenant -eq $PreviousSession.TokenTenantId

            if ($TenantSwitchNotTakenEffect) {
                Write-Warning (
                    "The Microsoft Graph token for tenant '$EffectiveTenant' was issued by tenant " +
                    "'$GrantedTenant', the same tenant that issued the token for the previous session, " +
                    "which named '$($PreviousSession.TenantId)'. If '$EffectiveTenant' is a name of tenant " +
                    "'$GrantedTenant', this is expected. Otherwise this sign-in did not switch tenants, and " +
                    "every call in this session acts on '$GrantedTenant' while reporting '$EffectiveTenant' -- " +
                    "Azure Resource Manager calls, including the ones that write role assignments, as well as " +
                    "Microsoft Graph calls. " +
                    "AzAuth does not send the named tenant with a new device code sign-in or with a managed " +
                    "identity request, so those tokens normally come from the signed-in account's or the " +
                    "identity's own tenant, and a client secret sign-in for the same application needs " +
                    "Connect-OER -Force to move to another tenant. Name the tenant by its tenant ID (a GUID) " +
                    "and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.")
            }

            # The authority-move -Force has now done its job: AzAuth cleared its static credential
            # and built a new one at THIS cloud's authority. Leaving Force on the splat would make
            # the ARM clone below discard that credential for no reason and construct another one at
            # the same authority. That matters for the credential types AzAuth reuses, such as a
            # client secret: without Force, its ARM call on the standard
            # 'Connect-OER -Environment USGov -IncludeARM' path reuses the credential the Graph call
            # just built. It is NOT what decides whether a second prompt appears. On DeviceCode the ARM
            # call builds a new credential anyway, since it passes no client id where the Graph call
            # passes one (measured offline), and on Interactive every call constructs a new credential
            # (decompiled, not executed). An explicit -ForceRefresh is the caller's own instruction
            # and survives.
            #
            # Removed HERE, inside the Graph-acquired branch, and nowhere else. When the Graph token
            # was cached and only ARM runs, the tracker can still legitimately name a different
            # authority than this cloud's -- a FAILED sovereign attempt moves it without rebuilding
            # the state (see the recording comment above) -- and that ARM call genuinely does need
            # the -Force to move the authority. Hoisting this removal out of this branch would break
            # exactly that case.
            if (-not $ForceRefresh) { $TokenParams.Remove('Force') }

            $SecureToken = [System.Net.NetworkCredential]::new('', $GraphToken.Token).SecurePassword

            # 'Global' omits the key ENTIRELY rather than passing 'Global' explicitly. The two are
            # equivalent to the SDK -- its default is the global cloud -- but only an absent key lets
            # a test prove the public call is byte-identical to the one this module has always made.
            $ConnectParams = @{
                AccessToken = $SecureToken
                NoWelcome   = $true
                ErrorAction = 'Stop'
            }
            if ($EffectiveEnvironment -ne 'Global') {
                $ConnectParams.Environment = $Endpoint.GraphEnvironment
            }

            # M4: wrap Connect-MgGraph so failures surface through Write-CmdletError, not bare exceptions.
            try {
                Connect-MgGraph @ConnectParams
            } catch {
                # Security hygiene, uniform with the Graph and ARM transport wrappers: scrub first, then
                # report. A failed ClientSecret token call binds the plaintext secret into the request
                # this record describes.
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError `
                    -Message ([System.Exception]::new("Failed to connect to Microsoft Graph: $($PSItem.Exception.Message)")) `
                    -InnerException $PSItem.Exception `
                    -ErrorId 'GraphConnectFailed' `
                    -Category AuthenticationError `
                    -TargetObject $EffectiveTenant `
                    -Cmdlet $PSCmdlet `
                    -Terminating
            }

            $script:_OERAuthState = @{
                TenantId         = $EffectiveTenant
                AuthMethod       = $EffectiveMethod
                ClientId         = $EffectiveClientId
                Environment      = $EffectiveEnvironment
                Account          = $GraphToken.Identity
                GraphTokenExpiry = $GraphToken.ExpiresOn.UtcDateTime
                # SEC: what the token itself says it was issued for, recorded ALONGSIDE TenantId and
                # never in place of it. TenantId is what the caller asked for and is what the cache-key
                # predicates ($GraphCached, $ArmCached, $ArmIdentityUnchanged) compare, so repointing it
                # at the granted value would silently change session-reuse semantics module-wide. This
                # field is evidence, not a key: where the request named a domain the guard above cannot
                # compare, and this is then the only record of which tenant actually answered.
                TokenTenantId    = $GrantedTenant
                # SEC: carry the cached ARM token into the rebuilt state ONLY when the tenant and auth
                # identity are unchanged. Otherwise drop it, so the next -IncludeARM call re-acquires for
                # the tenant actually being targeted instead of inheriting the previous customer's token.
                ArmToken         = if ($ArmIdentityUnchanged) { $script:_OERAuthState.ArmToken } else { $null }
                ArmTokenExpiry   = if ($ArmIdentityUnchanged) { $script:_OERAuthState.ArmTokenExpiry } else { $null }
                ArmResourceUrl   = if ($ArmIdentityUnchanged) { $script:_OERAuthState.ArmResourceUrl } else { $null }
                # Carried on the SAME condition as the ARM token it describes: an evidence field that
                # outlived the token it was recorded for would be worse than none at all.
                ArmTokenTenantId = if ($ArmIdentityUnchanged) { $script:_OERAuthState.ArmTokenTenantId } else { $null }
                ClaimsSatisfied  = [bool]$ClaimsChallenge
            }

            # The last session ESTABLISHED in this PowerShell process, for the post-call check above to
            # compare the next sign-in with. Written here, right after the state rebuild, so only a
            # session that was actually established is ever recorded -- never a token refused by
            # TenantMismatch, a failed token call or a failed Connect-MgGraph, each of which terminates
            # above before reaching this line.
            #
            # A tracker, not $script:_OERAuthState, since Disconnect-OER clears the state while what
            # decides the next token survives it. Measured offline: AzAuth's credential is process-wide
            # and nothing Disconnect-OER can reach clears it -- a second runspace reused it, and
            # Clear-AzTokenCache, with or without -Force, left it in place. Inferred from the decompiled
            # Azure.Identity, not executed: a device-code credential that has already signed in keeps
            # that account's authentication record on the instance AzAuth reuses, so the signed-in
            # account survives the disconnect too. Disconnecting before connecting to the next customer
            # is the natural way to switch, and it is the way Connect-OER's own help recommended before
            # this check existed ("To sign in as a different account or tenant, run Disconnect-OER
            # first"). Disconnect-OER must therefore NOT clear this tracker, exactly as it leaves
            # $script:_OERLastAuthorityHost and $script:_OERLastTokenRequest alone.
            #
            # Remaining limit: re-importing Omnicit.EntraRBAC resets this module's scope and this tracker
            # with it, so the first sign-in after such a re-import is not checked, while AzAuth's own
            # credential lives on -- measured: removing and re-importing AzAuth left the same credential
            # instance in place. That a re-import of Omnicit.EntraRBAC resets the tracker is inferred
            # from PowerShell module scoping, not executed.
            $script:_OERLastIssuedSession = @{ TenantId = $EffectiveTenant; TokenTenantId = $GrantedTenant }

            # M5: clear plaintext-bearing token variable to reduce its in-memory lifetime.
            $GraphToken = $null
        }

        # -- ARM token (optional) --
        if ($IncludeARM -and -not $ArmCached) {
            # M6: Clone() is a shallow clone - only top-level keys are mutated per-resource call,
            #     so nested objects (e.g. certificate) are safely shared without duplication.
            $ArmParams = $TokenParams.Clone()
            $ArmParams.Resource = $ArmResource
            $ArmToken = try {
                Invoke-AzTokenCall -TokenParameter $ArmParams -DeviceCodeFlow:($EffectiveMethod -eq 'DeviceCode')
            } catch {
                # Security hygiene, uniform with the Graph and ARM transport wrappers: scrub first, then
                # report. A failed ClientSecret token call binds the plaintext secret into the request
                # this record describes.
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError `
                    -Message ([System.Exception]::new("Failed to acquire an Azure Resource Manager token: $($PSItem.Exception.Message)")) `
                    -InnerException $PSItem.Exception `
                    -ErrorId 'ArmTokenAcquisitionFailed' `
                    -Category AuthenticationError `
                    -TargetObject $EffectiveTenant `
                    -Cmdlet $PSCmdlet
                return
            }

            # SEC: the same granted-tenant check on the ARM token, and it is not redundant with the
            # Graph one. AzAuth returns the same PipeHow.AzAuth.AzToken type here, so the tenant is
            # exposed identically; and when the Graph token was already cached this branch runs
            # ALONE, which makes it the only place a wrong-tenant ARM token could ever be caught.
            #
            # ABOVE the three assignments below, so a refused token is never cached for
            # Invoke-OERArmRequest to send. Deliberately TERMINATING, unlike the acquisition failure
            # just above which writes and returns: a token that could not be acquired leaves no ARM
            # token behind at all, whereas a token for the wrong tenant would become a usable one --
            # the caller must not be able to -ErrorAction SilentlyContinue past it and then call ARM.
            $GrantedArmTenant = $ArmToken.TenantId
            if ((Test-OERGuid -Value $EffectiveTenant) -and (Test-OERGuid -Value $GrantedArmTenant) -and
                $GrantedArmTenant -ne $EffectiveTenant) {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "The Azure Resource Manager token was issued for tenant '$GrantedArmTenant', not " +
                        "for the requested tenant '$EffectiveTenant'. Omnicit.EntraRBAC refuses to cache a " +
                        "token whose tenant does not match the session's: every later Azure call would act " +
                        "on '$GrantedArmTenant' while reporting '$EffectiveTenant'. Sign in again with an " +
                        "account that belongs to '$EffectiveTenant'.")) `
                    -ErrorId 'TenantMismatch' `
                    -Category AuthenticationError `
                    -TargetObject $EffectiveTenant `
                    -Cmdlet $PSCmdlet `
                    -Terminating
            }

            # Cache the ARM bearer token (as a SecureString) for Invoke-OERArmRequest to send directly.
            # We intentionally do NOT call Connect-AzAccount: Az.Accounts (5.x) cannot reliably hand an
            # externally acquired access token back to Invoke-AzRestMethod -- its AccessTokenAuthenticator
            # fails to retrieve the token for the management.azure.com resource -- so the module calls ARM
            # directly with this token. The plaintext is materialized only at the request boundary inside
            # the wrapper.
            $script:_OERAuthState.ArmToken       = [System.Net.NetworkCredential]::new('', $ArmToken.Token).SecurePassword
            $script:_OERAuthState.ArmTokenExpiry = $ArmToken.ExpiresOn.UtcDateTime
            $script:_OERAuthState.ArmResourceUrl = $ArmResource
            $script:_OERAuthState.ArmTokenTenantId = $GrantedArmTenant

            # M5: clear plaintext-bearing ARM token variable to reduce its in-memory lifetime.
            $ArmToken = $null
        }
    } finally {
        # M5: drop this function's references to the materialized plaintext secret once the token
        # calls are done -- on the terminating paths as well as the success path, which the previous
        # trailing cleanup line skipped. Both Clone()d splats are covered; the clones are shallow, so
        # each holds its own reference to the same string.
        #
        # Scope note: PowerShell has no block scope, so $GraphParams / $ArmParams declared inside the
        # try are visible here; they are $null when their branch did not run.
        if ($TokenParams.ContainsKey('ClientSecret')) { $TokenParams.ClientSecret = $null }
        if ($GraphParams -is [hashtable] -and $GraphParams.ContainsKey('ClientSecret')) { $GraphParams.ClientSecret = $null }
        if ($ArmParams   -is [hashtable] -and $ArmParams.ContainsKey('ClientSecret'))   { $ArmParams.ClientSecret   = $null }

        # AZURE_AUTHORITY_HOST is PROCESS-wide state that this function borrowed. Restore it here,
        # not after the token calls, so a terminating Write-CmdletError -- which unwinds straight
        # out of this function -- cannot leave the caller's process pinned to a sovereign authority
        # that every later unrelated Azure.Identity credential would then be constructed against.
        #
        # [NullString]::Value, not $null: PowerShell coerces $null to [string]::Empty when it binds
        # a .NET string parameter, and SetEnvironmentVariable with an EMPTY value does not delete the
        # variable -- it leaves AZURE_AUTHORITY_HOST in existence with no value, which is a different
        # state from the absent one this function found. [NullString]::Value is the only way to hand
        # a genuine null to the method from PowerShell. Measured, not assumed: with $null the
        # variable survives as '' and Test-Path Env:AZURE_AUTHORITY_HOST still reports $true.
        if ($AuthorityHostOverridden) {
            if ($null -eq $PreviousAuthorityHost) {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
            }
            else {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $PreviousAuthorityHost)
            }
        }
    }
}
