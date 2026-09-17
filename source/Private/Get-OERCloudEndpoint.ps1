function Get-OERCloudEndpoint {
    <#
    .SYNOPSIS
    Returns the Microsoft Graph and Azure Resource Manager endpoint set for a sovereign cloud.

    .DESCRIPTION
    Single owner of the cloud-to-endpoint table. Every place in this module that needs an authority
    host, a Graph resource/audience, a Graph service root, or an ARM resource/host for a given
    sovereign cloud reads it from here instead of hardcoding a second copy. The helper is pure: it
    makes no Graph or ARM call, acquires no token, and only looks up a value in a fixed table.

    Returns an object with seven properties:
      - Environment      the cloud key itself ('Global', 'USGov', 'USGovDoD', 'China').
      - GraphResource     the token audience handed to Get-AzToken -Resource. Keeps a trailing
                          slash, matching the exact string this module has always used for the
                          public cloud.
      - GraphEnvironment  the Graph environment name (matches Environment in every row today; kept
                          as its own property because it names a Graph-specific concept and is not
                          guaranteed to keep tracking Environment one-for-one forever).
      - GraphServiceRoot  the versioned Graph service root used to build an '@odata.id' bind
                          reference. Carries the API version and has NO trailing slash.
      - ArmResource       the ARM token audience. Keeps a trailing slash, matching the exact string
                          this module has always used for the public cloud.
      - ArmHost           the bare ARM host for the cloud, with NO trailing slash. No call site
                          reads this field today: Invoke-OERArmRequest builds its request path from
                          the ARM resource url cached on the auth state and derives the identical
                          string by trimming that value's trailing slash, so it never consults this
                          table at request time. The field is kept because it states the cloud's ARM
                          host plainly beside the rest of the row -- do not rewire the ARM transport
                          to consume it without a reason of its own, and do not assume a reader
                          exists just because the row names one.
      - AuthorityHost     the Microsoft Entra ID authority (STS) host for the cloud.

    GraphResource and GraphServiceRoot are deliberately SEPARATE properties and are not
    interchangeable: conflating them would emit a URL such as
    'https://graph.microsoft.com//v1.0/...' (resource string, trailing slash, plus the versioned
    root concatenated on top). Read the one each caller actually needs.

    Microsoft 365 GCC is a commercial-cloud tenant -- it uses the worldwide (public cloud) endpoints
    and is selected with 'Global', not a cloud of its own. There is no 'GCC' entry in this table
    because GCC is not a distinct sovereign boundary; it authenticates and calls Graph/ARM exactly
    like any other commercial tenant.

    The Microsoft Graph SDK also names 'DelosCloud', 'BleuCloud' and 'GovSGCloud' as environments.
    They are deliberately absent from this table: this module pairs every Graph endpoint with an
    Azure Resource Manager endpoint, and none of those three has an ARM counterpart in this design.
    Adding one would mean guessing an ArmResource/ArmHost pair this module cannot verify.

    -Environment deliberately carries NO ValidateSet on this private helper. The closed domain of
    supported clouds is enforced at the PUBLIC boundary instead -- Connect-OER and
    Initialize-OERAuth both attach a ValidateSet naming exactly the four clouds this table handles,
    so no caller reaches this helper with a value a user typed by hand. That leaves exactly one
    place an unsupported value can still arrive here: a future cloud added to those outer
    ValidateSets without a matching case being added to the switch below. An unhandled value must
    throw rather than silently fall back to the public-cloud row -- a silent fallback would send a
    sovereign-tenant credential and request at the wrong cloud boundary -- and leaving this
    parameter unvalidated is what keeps that throw reachable and provable by a live test rather than
    merely asserted by inspection. See tests/Unit/Private/Get-OERCloudEndpoint.Tests.ps1.

    .PARAMETER Environment
    The sovereign cloud to resolve endpoints for: 'Global', 'USGov', 'USGovDoD' or 'China'. Defaults
    to 'Global', which is this module's only supported cloud before this table existed and therefore
    must stay byte-for-byte identical to the literals it replaces. Any other value throws; the
    description above explains why this parameter carries no ValidateSet of its own.
    (Do not reflow that sentence so a line begins with a dot followed by a word: the help parser
    reads such a line as a help keyword, and a second .DESCRIPTION keyword inside this block wipes
    the whole comment-based help silently. That is exactly what it did until 2026-09-03.)

    .EXAMPLE
    Get-OERCloudEndpoint
    Returns the worldwide public-cloud endpoint set (the default).

    .EXAMPLE
    Get-OERCloudEndpoint -Environment 'USGovDoD'
    Returns the endpoint set for the US Government DoD cloud.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [string]$Environment = 'Global'
    )

    $Endpoint = switch ($Environment) {
        'Global' {
            [PSCustomObject]@{
                Environment      = 'Global'
                GraphResource    = 'https://graph.microsoft.com/'
                GraphEnvironment = 'Global'
                GraphServiceRoot = 'https://graph.microsoft.com/v1.0'
                ArmResource      = 'https://management.azure.com/'
                ArmHost          = 'https://management.azure.com'
                AuthorityHost    = 'https://login.microsoftonline.com/'
            }
        }
        'USGov' {
            [PSCustomObject]@{
                Environment      = 'USGov'
                GraphResource    = 'https://graph.microsoft.us/'
                GraphEnvironment = 'USGov'
                GraphServiceRoot = 'https://graph.microsoft.us/v1.0'
                ArmResource      = 'https://management.usgovcloudapi.net/'
                ArmHost          = 'https://management.usgovcloudapi.net'
                AuthorityHost    = 'https://login.microsoftonline.us/'
            }
        }
        'USGovDoD' {
            [PSCustomObject]@{
                Environment      = 'USGovDoD'
                GraphResource    = 'https://dod-graph.microsoft.us/'
                GraphEnvironment = 'USGovDoD'
                GraphServiceRoot = 'https://dod-graph.microsoft.us/v1.0'
                ArmResource      = 'https://management.usgovcloudapi.net/'
                ArmHost          = 'https://management.usgovcloudapi.net'
                AuthorityHost    = 'https://login.microsoftonline.us/'
            }
        }
        'China' {
            [PSCustomObject]@{
                Environment      = 'China'
                GraphResource    = 'https://microsoftgraph.chinacloudapi.cn/'
                GraphEnvironment = 'China'
                GraphServiceRoot = 'https://microsoftgraph.chinacloudapi.cn/v1.0'
                ArmResource      = 'https://management.chinacloudapi.cn/'
                ArmHost          = 'https://management.chinacloudapi.cn'
                AuthorityHost    = 'https://login.chinacloudapi.cn/'
            }
        }
        default {
            # No ValidateSet guards -Environment above (see .DESCRIPTION), so this is reachable
            # today, not merely defensive: Get-OERCloudEndpoint -Environment 'Germany' throws this.
            # Never fall back to the public-cloud row -- that would route a sovereign-tenant
            # credential and request at the wrong cloud boundary.
            throw "Get-OERCloudEndpoint: no endpoint table entry for cloud environment '$Environment'. Add a case to the switch in source/Private/Get-OERCloudEndpoint.ps1 before adding it to the -Environment ValidateSet on Connect-OER or Initialize-OERAuth."
        }
    }

    $Endpoint.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.CloudEndpoint')
    return $Endpoint
}
