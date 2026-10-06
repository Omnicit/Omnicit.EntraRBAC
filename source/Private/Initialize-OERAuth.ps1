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
    is what the cache-key predicates compare. A requested tenant that is neither a GUID nor
    'organizations' -- a verified domain, for example -- is first resolved to its tenant ID through the
    cloud authority's OpenID discovery document (Resolve-OERTenantDomain), after the cached return and
    before any token is requested. A lookup that fails raises a terminating TenantResolutionFailed
    error, and no token is requested and no AzAuth credential is built. The token request still names
    the tenant as given. When a token was issued for another tenant than the requested tenant ID --
    the GUID as given, or the one a domain resolved to -- a terminating TenantMismatch error is
    raised before the token is wired into Connect-MgGraph or cached for Azure Resource Manager, so a
    token minted for another tenant never becomes a usable session, whether the tenant was named by
    GUID or by domain. 'organizations' names no tenant and is not compared with one; an Azure
    Resource Manager token the sign-in acquires under it is compared with the session's Microsoft
    Graph token instead, and refused with TenantMismatch when the two report different tenant IDs,
    while one carried over a Microsoft Graph-only renewal is not compared again.

    The module's Microsoft Graph calls go out under whichever Microsoft Graph PowerShell SDK session the
    process holds, so every entry, the cached return included, first compares that session with the
    one this module connected (Get-OERGraphSessionState). The same session carries on as before. No
    session at all, after a Disconnect-MgGraph for example, is a cache miss and the module connects
    again with a token of its own -- which an inherited app-only identity cannot do, so it raises
    AppOnlySessionCredentialUnavailable. A session that another Connect-MgGraph started raises a
    terminating GraphSessionChanged error before any Graph call, and the module never switches the
    session back by itself, since that would move the other session's calls to this module's tenant.
    Only -ReclaimGraphSession, which Connect-OER passes, makes that a cache miss. When the refused
    request names another tenant, identity or cloud than the session's, the cached Azure Resource
    Manager token is dropped first, so a caller that carries on past the refusal has no token minted
    for the session's tenant to send to Azure under a request for another.

    Every entry first refuses a sign-in under a command whose own sign-in was refused: when a latched
    command stands on the call stack outside the command that called this function
    (Get-OERSignInRefusal -OutsideCaller), it raises a terminating SignInRefused naming that command,
    before any token call or Connect-MgGraph and without latching its caller (BL-74), so a cmdlet that
    a refused command calls never reaches a sign-in prompt. The caller's own latched frame, from an
    earlier refused sign-in in the same invocation, does not count, so that command may sign in again.

    Every other entry then latches the command that called this function (Lock-OERSignIn), and only a
    success releases it (Unlock-OERSignIn): the cached return, or a new connection that went the whole
    way. Every refusal, terminating error and early return -- ArmTokenAcquisitionFailed's included,
    so that command's Graph calls are refused too -- leaves that command latched, since outside any
    try a command carries on past a terminating error this function raises, and the module's
    transports send nothing for a latched command: they refuse each of its requests with
    SignInRefused, except that the Graph wrapper's session gate, which comes first, still reports a
    changed session as GraphSessionChanged. The latch is keyed on that command's invocation, so a
    pipeline neighbour, or any other command, that signs in successfully does not release it (a
    command it calls is refused before it signs in, as above). It
    stores only the boolean $true; its keys are the commands' own invocation objects, held weakly
    (the table keeps no command alive) and used only for their identity, and the decision never
    reads a key.

    Where it releases the latch, a success also remembers, keyed on the same invocation, which identity
    the calling command signed in as (Register-OERSignInIdentity): the tenant, the method, the client
    and the cloud, never a token. The module's transports refuse with SignInSuperseded a request made
    while any command on the call stack remembers another identity than the module's state now
    carries. In a pipeline every begin block runs first, so in
    New-OERGroup -TenantId A ... | Add-OERGroupMember -TenantId B the second sign-in would otherwise
    make the first command create its group in B; and an outer command's nested cmdlets, which inherit
    the session, would otherwise send under a state a later pipeline command switched.

    A sign-in that does not succeed also leaves the session uncertain (A10, BL-89): the module's session
    is still the one an earlier sign-in left -- the previous tenant's, or none -- and outside any try the
    script carries on, so a command that names no tenant would act on that previous tenant. Every entry
    past the BL-74 check therefore marks the session uncertain (Set-OERSessionUncertain), directly after
    it latches its caller, and a success clears the marker when the sign-in named its tenant -- a
    -TenantId other than 'organizations', and not a transport's own refresh (-ForceRefresh or
    -ClaimsChallenge) -- or was Connect-OER's (-ReclaimGraphSession); any other success puts back the
    value it found. While the marker is set, a sign-in that names no tenant is refused with a terminating
    SignInRefused (New-OERSignInRefusedError -SessionUncertain), after the GraphSessionChanged refusal and
    before the cached return and any token call, and its caller stays latched. Connect-OER sets the marker
    first thing, and Disconnect-OER clears it.

    Before a client secret token request, a warning is written when the token request that last made
    AzAuth build its credential in this PowerShell session was also a client secret request, for the
    same application but a different tenant, and no Force is on the call (neither -ForceRefresh nor
    the one this function adds for a cloud switch). AzAuth keeps the credential it built for that
    tenant for the whole process and reuses it for that application, so the new tenant is not
    reached. The warning does not refuse the sign-in, but a caller running with -WarningAction Stop
    or $WarningPreference = 'Stop' is stopped at it, before its token request is made. A sign-in
    whose token comes back from another tenant than the one it names is refused with TenantMismatch,
    as above, whether the tenant was named by GUID or by domain.

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
    The Entra ID tenant: a tenant ID (GUID) or a verified domain. A domain is looked up in the cloud's
    OpenID discovery document before any token is requested, and every token must then be issued for
    the tenant ID it resolves to. Any other value than a GUID or 'organizations' -- 'common', for
    example -- is looked up too, and is refused with TenantResolutionFailed when it names no tenant.
    When omitted, the tenant of the current session is used; when there is no session,
    'organizations' is used. A value naming a different tenant than the session inherits nothing
    else from it.

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

    .PARAMETER ReclaimGraphSession
    Treat a Microsoft Graph PowerShell SDK session that another Connect-MgGraph started after this
    module connected as a cache miss, and connect again, instead of refusing with GraphSessionChanged.
    Only Connect-OER passes it: an explicit sign-in is the operator's instruction to take the session
    back. No other caller may pass it, since that would switch the other session's calls to this
    module's tenant.

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
        [string]$Environment,

        # Connect-OER only; see .PARAMETER ReclaimGraphSession.
        [switch]$ReclaimGraphSession
    )

    # SEC (BL-74): a sign-in under a command whose own sign-in was refused is refused here, before
    # anything else. That command carries on past its refusal outside any try and calls cmdlets that
    # sign in again without -TenantId; the transports refuse every request it makes (A19), but its
    # nested sign-ins still ran, and near the cached token's expiry one of them would reach
    # Get-AzToken -- an interactive or device code prompt -- or Connect-MgGraph for a command that
    # sends nothing. Only a frame OUTSIDE the calling command counts (Get-OERSignInRefusal
    # -OutsideCaller): the caller's own latched frame, from an earlier refused sign-in in the same
    # invocation, is A19's same-frame retry and keeps its chance to sign in. Placed before
    # Lock-OERSignIn, so the refusal latches nothing of its own; the outer command's latch already
    # refuses every request the caller makes while it runs. No token call, no Connect-MgGraph.
    $OuterRefused = Get-OERSignInRefusal -OutsideCaller
    if ($OuterRefused) {
        Write-CmdletError -ErrorRecord (New-OERSignInRefusedError -Command $OuterRefused) -Cmdlet $PSCmdlet -Terminating
        return
    }

    # SEC (A19): the sign-in latch. Set directly after the BL-74 check above, for the command that
    # called this function, and released only where a sign-in succeeded: at the cached return below,
    # and as the last statement of a new connection that went the whole way -- after the ARM step,
    # inside the big try and never in its finally. Every refusal, terminating error and early return
    # leaves it set, ArmTokenAcquisitionFailed's early return included, although the Graph session is
    # connected by then, so that command's Graph calls are refused as well as its ARM calls. The BL-74
    # refusal above is the one exception: it comes before this latch, so it latches nothing of its own
    # -- the latched outer command it found already refuses the caller's requests. A terminating error
    # ends this function but not the command that called it: outside any try that command carries on
    # with its next statement (see the SEC (A18) comment below), so a command whose sign-in for tenant
    # B failed or was refused would otherwise send its Graph and ARM calls under the session tenant A
    # left -- for Invoke-OERStructure -Prune, B's document applied to A. Invoke-OERGraphRequest and
    # Invoke-OERArmRequest read the latch through Get-OERSignInRefusal before every request and refuse
    # every request of a latched command with SignInRefused (New-OERSignInRefusedError) -- the Graph
    # wrapper after its session gate, which still reports a changed session as GraphSessionChanged.
    #
    # Keyed on the calling command's INVOCATION, not a module boolean that any success releases.
    # Almost every public cmdlet calls this function in its begin block, and the apply handlers call
    # public cmdlets (New-OERGroup, Set-OERGroup, Get-OERRoleAssignment, ...) that call it again
    # without -TenantId, inherit the session and hit the cache: inside a refused
    # Invoke-OERStructure -TenantId B, the first nested cmdlet would release a boolean and every later
    # write would go to A. (Since BL-74 that nested sign-in is refused before it reaches the cache.)
    # A pipeline does the same, and BL-74 does not reach it: in Get-OERGroup -TenantId B |
    # Remove-OERGroup both begin blocks run first, so Remove-OERGroup's cache hit would release a
    # boolean before Get-OERGroup's process block reads. A transport refuses when ANY frame on its
    # call stack is latched, so a command's own success releases only its own entry: a refused
    # command elsewhere stays latched, and a pipeline neighbour's success releases only its own. A
    # command that finishes leaves every call stack, so the latch does not refuse the command after
    # it: Connect-OER, or a new command whose sign-in succeeds, sends again.
    #
    # The calling command is the IMMEDIATE caller. Inside a transport's own refresh -- the claims
    # step-up or the token-rejected retry of Invoke-OERGraphRequest, the 401 retry of
    # Invoke-OERArmRequest -- that is the transport's nested function (Invoke-GraphSingle,
    # Invoke-ArmCallWithRefresh): a refusal there refuses only that retry, and the command's next
    # request is a new transport call (step 4b round 1, Ruling R5; docs/development/rationale.md,
    # auth-state). Everywhere else this function is called directly in the command's own function,
    # never from a nested function or a script block, which would latch a frame that ends at once;
    # gate 10 of tests/QA/sourcehygiene.tests.ps1 holds every call site to that.
    #
    # The table ($script:_OERSignInLatch, a ConditionalWeakTable) stores only the boolean $true. Its
    # keys are the commands' own invocation objects -- each carries its command's bound parameters, a
    # tenant among them -- held weakly, so the table keeps no command alive, and used only for their
    # identity: the decision never reads a key. This function adds no other module variable for it.
    #
    # SEC (A20): the sign-in memory, beside the latch. Where the latch is released -- the cached return
    # and the last statement of the big try -- the module also remembers, keyed on the same invocation
    # ($SignInCaller), which identity the calling command signed in as (Register-OERSignInIdentity):
    # the tenant (the one the Graph token was issued for, when that is a GUID), method, client and
    # cloud, as one string from Get-OERSignInIdentity, never a token. Both transports read it through
    # Get-OERSignInSupersession before every request and refuse with SignInSuperseded
    # (New-OERSignInSupersededError) a request made while ANY frame on the call stack remembers another
    # identity than the state now carries. The pipeline case: every begin block runs first, so in
    # New-OERGroup -TenantId A ... | Add-OERGroupMember -TenantId B the second sign-in switches the
    # state to B before New-OERGroup's process block runs, and the group would otherwise be created in
    # B -- both sign-ins succeed, so neither the latch nor the A18 session gate sees it. And the nested
    # case: an outer command whose nested cmdlets sign in without -TenantId inherit whatever state a
    # later pipeline command switched to, so the walk does not stop at a nested frame whose memory
    # equals the state. A command with no memory (a unit test that mocks this function) is not
    # compared. The table ($script:_OERSignInIdentity, a ConditionalWeakTable) is the only other
    # module variable this adds; its values are those identity strings.
    #
    # SEC (A10, BL-89): the session-uncertain marker, set as the statement directly after the latch, so
    # every refusal from here on -- ArmTokenAcquisitionFailed's early return and GraphSessionChanged
    # included -- leaves the session uncertain, while the BL-74 refusal above, for a sign-in never
    # attempted, leaves the marker as it was. $SessionWasUncertain keeps what the marker said before this
    # entry: the refusal below the GraphSessionChanged one reads it, and the two success ends put it back
    # unless this sign-in clears it ($ClearsUncertainty). Set-OERSessionUncertain is the marker's single
    # owner, and $script:_OERSessionUncertain the one module variable it keeps; gate 10 of
    # tests/QA/sourcehygiene.tests.ps1 holds where the three calls in this function stand.
    $SignInCaller = Lock-OERSignIn
    [bool]$SessionWasUncertain = Set-OERSessionUncertain -Value $true

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

    # SEC (A10): whether this sign-in names its tenant, for the session-uncertain marker. 'organizations'
    # names none. A transport's own refresh (-ForceRefresh or -ClaimsChallenge without
    # -ReclaimGraphSession) passes the state's tenant on the command's behalf, so it neither counts as
    # naming one nor clears the marker; Connect-OER (-ReclaimGraphSession) always does.
    [bool]$TenantNamed = [bool]$TenantId -and $TenantId -ne 'organizations'
    [bool]$ClearsUncertainty = $ReclaimGraphSession -or
        ($TenantNamed -and -not $ForceRefresh -and -not $ClaimsChallenge)

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

    # SEC (A18): the Microsoft Graph PowerShell SDK session the process holds, compared with the one
    # this module connected -- read ONCE per entry, here, for the two GraphSession terms of
    # $GraphCached and for the refusal below the ARM predicates. See the SEC (A18) comment there.
    $GraphSession = Get-OERGraphSessionState

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
    # The two GraphSession terms are A18's: a cached token describes nothing once the process no
    # longer holds the session it was connected to. Changed gets past the refusal below, which sits
    # before the cached return, only under -ReclaimGraphSession.
    [bool]$GraphCached = $script:_OERAuthState -and
        $script:_OERAuthState.AuthMethod -eq $EffectiveMethod -and
        $script:_OERAuthState.ClientId   -eq $EffectiveClientId -and
        $script:_OERAuthState.TenantId   -eq $EffectiveTenant -and
        $script:_OERAuthState.Environment -eq $EffectiveEnvironment -and
        $GraphSession -ne 'Absent' -and
        $GraphSession -ne 'Changed' -and
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

    # SEC (A18): the module's Graph calls go out under whichever Microsoft Graph PowerShell SDK session
    # the PROCESS holds (INFERRED from the SDK source, and measured live by check 1.3 of this change's
    # live checklist) -- Invoke-OERGraphRequest passes no token of its own, and the SDK keeps one
    # session per process -- so every predicate above describes the session those calls will use only
    # while it is still the one this module connected. An operator's own Connect-MgGraph, or another
    # tool's, replaces it; before this check the module's following Graph reads and writes went to that
    # session's tenant while $script:_OERAuthState still named the first, and ARM, which keeps its own
    # token, pointed at another tenant than Graph. Compared at EVERY entry, the cached return included.
    #
    # Untracked (no state, or one this function did not build) compares nothing and calls nothing.
    # Absent (no session at all, after Disconnect-MgGraph for example) is a cache miss above, and the
    # module connects again with a token of its own exactly as after a renewal; an inherited app-only
    # identity cannot, and gets AppOnlySessionCredentialUnavailable. Changed is refused here, before
    # the cached return and before any Graph call, and the module never switches the session back by
    # itself: that would silently move the other session's calls to this module's tenant. Only
    # Connect-OER, an explicit instruction to take the session back, passes -ReclaimGraphSession, which
    # makes Changed a cache miss instead. Nothing between the session read above and this refusal
    # calls anything: only the predicate assignments sit there.
    #
    # This refusal ends this function, but NOT the cmdlet that called it. Measured 2026-10-05 in
    # PowerShell 7: a terminating error a nested advanced function raises with ThrowTerminatingError
    # stops that function, and its caller carries on with its next statement unless a try or trap is
    # active somewhere up the call stack -- with the default error preference, not only under
    # -ErrorAction SilentlyContinue. No public cmdlet wraps its Initialize-OERAuth call, so the cmdlet
    # still reaches Invoke-OERGraphRequest, which is why that wrapper checks the session again before
    # every Graph call. This refusal, like every other one in this function, also leaves the sign-in
    # latch set for the calling command (SEC (A19), at the top of this function), so that command
    # sends nothing: the Graph wrapper's session gate, which comes before its latch gate, refuses the
    # command's Graph calls with GraphSessionChanged while the session stays changed, and the ARM
    # wrapper's latch gate refuses its ARM calls with SignInRefused. Unit tests cannot see the carrying
    # on from inside Pester, whose try makes the refusal propagate; the wrappers' tests prove it in a
    # runspace with no try.
    #
    # A refused request that names another tenant, identity or cloud first drops the cached ARM token.
    # The cmdlet carries on past the refusal, as above, but since A19 the latch refuses its Azure
    # Resource Manager calls (SignInRefused) before Invoke-OERArmRequest materializes a bearer. The
    # drop predates the latch and stays as a second guard that does not depend on it, since
    # Invoke-OERArmRequest compares nothing: it sends $script:_OERAuthState.ArmToken. Left in place,
    # before the latch existed, a token minted for the module's own tenant answered a request for
    # another one -- measured by the final review of A18, in a runspace with no try:
    # Get-OERSubscription -TenantId naming a second tenant was refused, then listed the FIRST tenant's
    # subscriptions with the first tenant's token. A request naming another tenant, identity or cloud
    # must not leave a token minted for the old one behind: the rule the state rebuild below already
    # applies on $ArmIdentityUnchanged, applied here because the refusal never reaches the rebuild.
    # With no token, a request that reached the send would carry an empty bearer, ARM would answer 401,
    # and the 401 path raises instead of re-acquiring (its forced refresh is refused here as well, and
    # an app-only session never re-acquires), so no request carries a credential for the wrong tenant.
    # ONLY then: a refused request for the module's own tenant, identity and cloud keeps its token,
    # since that token is for the tenant the request meant. The cost: once Connect-OER has taken the
    # session back, an app-only session needs Connect-OER -IncludeARM again before an Azure cmdlet,
    # since the module never keeps the certificate or the client secret; a delegated or managed
    # identity session re-acquires its ARM token by itself.
    if ($GraphSession -eq 'Changed' -and -not $ReclaimGraphSession) {
        if (-not $ArmIdentityUnchanged) {
            $script:_OERAuthState.ArmToken         = $null
            $script:_OERAuthState.ArmTokenExpiry   = $null
            $script:_OERAuthState.ArmResourceUrl   = $null
            $script:_OERAuthState.ArmTokenTenantId = $null
        }
        Write-CmdletError -ErrorRecord (New-OERGraphSessionChangedError) -Cmdlet $PSCmdlet -Terminating
    }

    # SEC (A10, BL-89): while the session is uncertain, a sign-in that names no tenant is refused. A
    # sign-in that fails or is refused leaves the session an earlier sign-in left in place -- the
    # previous tenant's, or none -- and outside any try the script carries on: in
    # foreach ($T in $Profiles) { Connect-OER -TenantAlias $T; Invoke-OERStructure -Path "$T.json" -Prune }
    # a refused Connect-OER let the next Invoke-OERStructure, which names no tenant, apply X's document,
    # prune included, in the previous tenant. Placed after the GraphSessionChanged refusal, so a changed
    # session still reads GraphSessionChanged, and before the cached return and every token call, so the
    # refused sign-in requests nothing and connects nothing. The caller stays latched: the transports
    # refuse its requests with SignInRefused, and the cmdlets it calls are refused by BL-74. A sign-in
    # that names its tenant gets past this check, and so does Connect-OER's (-ReclaimGraphSession),
    # named tenant or not; either clears the marker when it succeeds.
    if ($SessionWasUncertain -and -not $TenantNamed -and -not $ReclaimGraphSession) {
        [string]$UncertainCaller = if ($SignInCaller -and $SignInCaller.MyCommand.Name) { $SignInCaller.MyCommand.Name } else { 'a script block' }
        Write-CmdletError -ErrorRecord (New-OERSignInRefusedError -Command $UncertainCaller -SessionUncertain) -Cmdlet $PSCmdlet -Terminating
        return
    }

    if ($GraphCached -and $ArmCached) {
        Write-Verbose "[Initialize-OERAuth] Returning cached auth state for tenant '$EffectiveTenant'."
        # SEC (A19): a cache hit is a success; release the calling command's latch. SEC (A20): and
        # remember which identity it signed in as. SEC (A10): and clear the session-uncertain marker
        # when this sign-in named its tenant or was Connect-OER's, or put back what it found.
        Unlock-OERSignIn -Invocation $SignInCaller
        Register-OERSignInIdentity -Invocation $SignInCaller
        $null = Set-OERSessionUncertain -Value ($SessionWasUncertain -and -not $ClearsUncertainty)
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
                "The cached session for tenant '$EffectiveTenant' is app-only ($EffectiveMethod)" +
                "$(if ($GraphSession -eq 'Absent') { ', its Microsoft Graph PowerShell SDK session was closed outside the module (by Disconnect-MgGraph, for example),' })" +
                " and a new " +
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

    # SEC (BL-12, decided by Philip 2026-10-06, P-2): a tenant named by domain is resolved to its tenant
    # ID before any token is requested, through the cloud authority's OpenID discovery document
    # (Resolve-OERTenantDomain, the one network call outside the Microsoft Graph and Azure Resource
    # Manager transports, and the one deliberately unauthenticated call), and every token is then
    # compared with that ID (TenantMismatch, below): a token carries its tenant as a GUID, so a domain
    # is compared through the GUID it resolves to, and a device code, managed identity or reused client
    # secret sign-in that comes back from another tenant is refused. A GUID needs no lookup;
    # 'organizations' names no tenant and is not compared. Placed after the cached return -- a session
    # that needs no new token was verified when it was established -- and after the credential checks,
    # but before the trackers below move and before any token call, so a refused lookup builds no AzAuth
    # credential and requests nothing. A failed lookup is raised after the try statement, not inside its
    # catch: a terminating error suppressed inside a catch resumes after the whole try statement.
    $ExpectedTenantId = $null
    $TenantResolutionError = $null
    if (Test-OERGuid -Value $EffectiveTenant) {
        $ExpectedTenantId = $EffectiveTenant
    }
    elseif ($EffectiveTenant -ne 'organizations') {
        try {
            $ExpectedTenantId = Resolve-OERTenantDomain -Domain $EffectiveTenant -Environment $EffectiveEnvironment
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $TenantResolutionError = $PSItem
        }
    }
    if ($null -ne $TenantResolutionError) {
        Write-CmdletError `
            -Message ([System.Exception]::new(
                "Could not resolve tenant '$EffectiveTenant' to its tenant ID: " +
                "$($TenantResolutionError.Exception.Message) Omnicit.EntraRBAC checks the tenant every token " +
                "is issued for, and a tenant named by domain is checked through its tenant ID, so no token " +
                "was requested. Check the domain and the cloud (-Environment), or name the tenant by its " +
                "tenant ID (a GUID).")) `
            -InnerException $TenantResolutionError.Exception `
            -ErrorId 'TenantResolutionFailed' `
            -Category AuthenticationError `
            -TargetObject $EffectiveTenant `
            -Cmdlet $PSCmdlet `
            -Terminating
        return
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
        # secret request replaces it. The TenantMismatch check after each token observes what this one
        # cannot predict: the tenant the token was issued for, compared with the tenant ID the request
        # named or its domain resolved to.
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
            # Both values compared are GUIDs. The requested side is $ExpectedTenantId, set before any
            # token was requested (SEC (BL-12) above): the tenant ID as named, or the one a domain
            # resolved to through the cloud authority's OpenID discovery document. A tenant named by
            # domain is therefore compared exactly like one named by GUID, while the token request
            # itself still names the tenant as given. 'organizations' names no tenant: $ExpectedTenantId
            # is $null for it, and that term is what excludes it -- a term an input falsifies, so it
            # stays on its own and mutation-provable. A granted value that is not a GUID (AzAuth
            # returned no tenant at all) is not compared either; TokenTenantId below records it as it
            # is. Test-OERGuid is the module's single GUID predicate -- never re-implement its regex.
            # -ne on strings is case-insensitive in PowerShell, so a GUID typed in upper case still
            # compares equal to the lower-case one Entra returns. The message names the tenant as the
            # caller gave it and, for a domain, the tenant ID it resolved to.
            #
            # Why a token can come back from another tenant than the one named. Measured offline, with
            # the network blocked: every device-code request went to 'organizations' whatever -Tenant
            # said, -Force included; a managed identity request was byte-identical for any tenant; and
            # a client secret credential reused under AZURE_IDENTITY_DISABLE_MULTITENANTAUTH sent its
            # token request to the PREVIOUS tenant (the pre-call warning above predicts that one).
            # Inferred, not executed: a device-code token is issued for the tenant of the account that
            # signs in, and a managed identity token for the identity's own tenant. The DEVICE-CODE
            # half of that inference is weakened, not withdrawn, by a RECORDED OBSERVATION from the
            # 2026-09-15/16 live run, in which every device-code sign-in that NAMED a tenant came back
            # issued by that tenant. Still DECOMPILED: a device-code credential reused after a
            # SUCCESSFUL sign-in first attempts silent reacquisition for the requested tenant.
            # CONTRADICTED BY MEASUREMENT, 2026-09-16, twice on a healthy connection: when such a
            # credential names another tenant without -Force there is no fall-back to a new device
            # code -- the call never returns, and -Force cured it every time.
            #
            # MEASURED live, 2026-09-15/16, against real tokens: AzToken.TenantId carries the acquired
            # token's own tid claim, not an echo of the requested value (checklist 4.1, 4.2 and 4.3a,
            # corroborated by 2.7b). DECOMPILED and still NOT measured: the property falls back to
            # echoing the REQUESTED tenant when the token carries no tid claim at all -- a domain then,
            # which is not a GUID and is not compared, or the requested GUID, which compares equal.
            #
            # The tenant-switch warning that used to follow this check, comparing the granted tenant with
            # the previous session's, is retired: it existed because a domain could not be compared here,
            # and after the lookup it could only fire for a domain that names the very tenant its token
            # came from -- a correct sign-in. docs/development/rationale.md#switching-tenants-in-one-process
            # is the record that governs this check and the evidence above; do not grow a second copy of
            # it here.
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
            if ($ExpectedTenantId -and (Test-OERGuid -Value $GrantedTenant) -and
                $GrantedTenant -ne $ExpectedTenantId) {
                [string]$RequestedLabel = if ($ExpectedTenantId -ne $EffectiveTenant) {
                    "'$EffectiveTenant' (tenant ID '$ExpectedTenantId')"
                } else {
                    "'$EffectiveTenant'"
                }
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "The Microsoft Graph token was issued for tenant '$GrantedTenant', not for the " +
                        "requested tenant $RequestedLabel. Omnicit.EntraRBAC refuses a session whose " +
                        "cached tenant does not describe the token beneath it: every later call would act " +
                        "on '$GrantedTenant' while reporting '$EffectiveTenant'. Sign in again with an " +
                        "account that belongs to '$EffectiveTenant'.")) `
                    -ErrorId 'TenantMismatch' `
                    -Category AuthenticationError `
                    -TargetObject $EffectiveTenant `
                    -Cmdlet $PSCmdlet `
                    -Terminating
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
                # field is not a cache key: the guard above has compared it with the tenant ID the
                # request named or its domain resolved to, and for a domain this is the session's record
                # of that tenant ID. The sign-in identity (Get-OERSignInIdentity) uses it as its tenant
                # term when it is a GUID (BL-77).
                TokenTenantId    = $GrantedTenant
                # The signed-in identity's own object id, from the Graph token's oid claim -- the
                # user on a delegated sign-in, the service principal on an app-only one. Read by
                # Get-OERSignedInObjectId so the directory-role prune never removes the caller's own
                # assignments. The token itself is never stored.
                SignedInObjectId = Get-OERTokenObjectId -Token $SecureToken
                # SEC (A18): which Microsoft Graph PowerShell SDK session this module just connected,
                # read straight after its own Connect-MgGraph above. Get-OERGraphSessionState compares
                # it with the session the process holds at every later entry here and before every
                # Graph call, since Invoke-OERGraphRequest sends no token of its own. Never a token and
                # never the context object: see Get-OERGraphSessionFingerprint. The key is written even
                # when the value is $null, so a session whose context could not be read is still
                # compared -- and refused when someone else's appears.
                GraphSessionFingerprint = Get-OERGraphSessionFingerprint
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

            # SEC: the same granted-tenant check on the ARM token, against the same $ExpectedTenantId --
            # the tenant ID as named, or the one a domain resolved to, so both values compared are GUIDs
            # and 'organizations', for which it is $null, is not compared -- and it is not redundant with
            # the Graph one. AzAuth returns the same PipeHow.AzAuth.AzToken type here, so the tenant is
            # exposed identically; and when the Graph token was already cached this branch runs ALONE --
            # after a lookup of its own, since an ARM-only acquisition also gets past the cached return --
            # which makes it the only place a wrong-tenant ARM token could ever be caught. The ARM
            # acquisition can also be a sign-in of its own. On DeviceCode the delegated Graph call passes
            # a client id and this one passes none, so AzAuth builds a separate credential for it
            # (measured offline, see the comment above Invoke-AzTokenCall); on Interactive and
            # ClientCertificate AzAuth builds a new credential on every call (decompiled). On those
            # three its token may come back from another tenant than the Graph token's. MEASURED live,
            # 2026-09-16, for a managed identity sign-in with -IncludeARM only: on a switch that did not
            # take effect the ARM token's tenant equalled the Graph token's.
            # docs/development/rationale.md#switching-tenants-in-one-process governs.
            #
            # ABOVE the assignments below, so a refused token is never cached for
            # Invoke-OERArmRequest to send. Deliberately TERMINATING, unlike the acquisition failure
            # just above which writes and returns: a token that could not be acquired leaves no ARM
            # token behind at all, whereas a token for the wrong tenant would become a usable one --
            # the caller must not be able to -ErrorAction SilentlyContinue past it and then call ARM.
            $GrantedArmTenant = $ArmToken.TenantId
            if ($ExpectedTenantId -and (Test-OERGuid -Value $GrantedArmTenant) -and
                $GrantedArmTenant -ne $ExpectedTenantId) {
                [string]$RequestedLabel = if ($ExpectedTenantId -ne $EffectiveTenant) {
                    "'$EffectiveTenant' (tenant ID '$ExpectedTenantId')"
                } else {
                    "'$EffectiveTenant'"
                }
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "The Azure Resource Manager token was issued for tenant '$GrantedArmTenant', not " +
                        "for the requested tenant $RequestedLabel. Omnicit.EntraRBAC refuses to cache a " +
                        "token whose tenant does not match the session's: every later Azure call would act " +
                        "on '$GrantedArmTenant' while reporting '$EffectiveTenant'. Sign in again with an " +
                        "account that belongs to '$EffectiveTenant'.")) `
                    -ErrorId 'TenantMismatch' `
                    -Category AuthenticationError `
                    -TargetObject $EffectiveTenant `
                    -Cmdlet $PSCmdlet `
                    -Terminating
            }

            # SEC (BL-77; final review M1, Ruling F3): with no tenant named there is no tenant ID to
            # compare with -- $ExpectedTenantId is $null for 'organizations' -- so the ARM token is
            # compared with the Graph token of the same session instead: $script:_OERAuthState.TokenTenantId,
            # from the Graph token this call acquired or the cached one an ARM-only acquisition runs beside.
            # The sign-in identity's tenant term is that Graph tenant (BL-77), so without this an
            # interactive sign-in naming no tenant whose Graph prompt one account answered and whose ARM
            # prompt another account answered would hold two tenants under one identity: no supersession
            # sees it, and in X -TenantId <GUID> | Y -TenantId organizations, X's Azure calls would go out
            # with the other tenant's ARM token. Compared only when both values are GUIDs, so a Graph token
            # without a GUID tenant leaves nothing to compare with (the same limit as the check above).
            # Terminating, above the assignments below, for the reason the check above gives. Every term on
            # its own line and independently deletable, so each stays mutation-provable.
            $SessionGraphTenant = $script:_OERAuthState.TokenTenantId
            if (-not $ExpectedTenantId -and
                (Test-OERGuid -Value $GrantedArmTenant) -and
                (Test-OERGuid -Value $SessionGraphTenant) -and
                $GrantedArmTenant -ne $SessionGraphTenant) {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "The Azure Resource Manager token was issued for tenant '$GrantedArmTenant', but the " +
                        "Microsoft Graph token of the same session was issued for tenant '$SessionGraphTenant'. " +
                        "The sign-in named no tenant ('$EffectiveTenant'), so the two tokens are compared with " +
                        "each other, and Omnicit.EntraRBAC refuses to cache an Azure Resource Manager token " +
                        "for another tenant than the session's Microsoft Graph token: every later Azure call " +
                        "would act on '$GrantedArmTenant' while every Microsoft Graph call acts on " +
                        "'$SessionGraphTenant'. Sign in again with one account for both, or name the tenant " +
                        "with -TenantId.")) `
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

        # SEC (A19): the new connection went the whole way -- Graph connected or cached, and the ARM
        # token acquired or not asked for -- so release the calling command's latch, and (SEC (A20))
        # remember which identity it signed in as, and (SEC (A10)) clear the session-uncertain marker
        # when this sign-in named its tenant or was Connect-OER's, or put back what it found. The
        # release, the memory and the marker are the LAST statements of this try and deliberately not in
        # the finally below: the finally also runs on every terminating error and on
        # ArmTokenAcquisitionFailed's early return, which must leave the command latched, must not
        # remember that sign-in and must leave the session uncertain.
        Unlock-OERSignIn -Invocation $SignInCaller
        Register-OERSignInIdentity -Invocation $SignInCaller
        $null = Set-OERSessionUncertain -Value ($SessionWasUncertain -and -not $ClearsUncertainty)
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
