BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERCatalog' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'gets a catalog by id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'cat-1'; displayName = 'CAT-IT-Core' }
        } -ParameterFilter { $Uri -like '*catalogs/cat-1*' }
        $Result = Get-OERCatalog -Id 'cat-1'
        $Result.Id | Should -Be 'cat-1'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Catalog'
    }

    It 'lists all catalogs when no filter is given' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'a'; displayName = 'A' }, @{ id = 'b'; displayName = 'B' }) }
        }
        $Result = Get-OERCatalog
        $Result.Count | Should -Be 2
        $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Catalog'
    }

    It 'filters by display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'cat-9'; displayName = 'CAT-IT-Core' }) }
        }
        Get-OERCatalog -DisplayName 'CAT-IT-Core' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*displayName eq 'CAT-IT-Core'*"
        }
    }

    It 'percent-encodes a display name containing reserved characters so the query survives transport' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'cat-9'; displayName = 'R&D + Core' }) }
        }
        $Result = Get-OERCatalog -DisplayName 'R&D + Core'
        $Result.Id | Should -Be 'cat-9'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*displayName eq 'R%26D%20%2B%20Core'*"
        }
    }

    It 'percent-encodes a -Filter value containing reserved characters' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @() }
        }
        Get-OERCatalog -Filter "startswith(displayName,'R&D')" | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -notmatch '&D' -and $Uri -match '%26D'
        }
    }

    It 'has a registered format view for the Catalog type' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'cat-1'; displayName = 'CAT-IT-Core' } } -ParameterFilter { $Uri -like '*catalogs/cat-1*' }
        $Formatted = Get-OERCatalog -Id 'cat-1' | Format-Table | Out-String
        $Formatted | Should -Match 'DisplayName'
    }

    It 'surfaces a Graph failure as a non-terminating error for -Id and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        } -ParameterFilter { $Uri -like '*catalogs/cat-1*' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERCatalog -Id 'cat-1' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Get-OERCatalog' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'surfaces a Graph failure as a non-terminating error for the list path and emits nothing' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('TooManyRequests: throttled.'),
                'TooManyRequests',
                [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERCatalog -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TooManyRequests,Get-OERCatalog' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'passes -All to the list read (closes rt-graph-list-reads-first-page-only)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'a'; displayName = 'A' }, @{ id = 'b'; displayName = 'B' }) }
        }
        Get-OERCatalog | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $All }
    }

    It 'does NOT pass -All to the single-entity -Id read' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'cat-1'; displayName = 'CAT-IT-Core' }
        } -ParameterFilter { $Uri -like '*catalogs/cat-1*' }
        Get-OERCatalog -Id 'cat-1' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { -not $All }
    }
}

Describe 'Get-OERCatalog bearer hygiene: no copy in -ErrorVariable or $global:Error keeps the header (BL-157, BL-109 F4)' {
    # WHAT THIS PROVES. A failed Graph read leaves several copies of the failure behind: the engine
    # deposits the SDK's raw record into the caller's -ErrorVariable at every call boundary it
    # crosses, even after the wrapper's catch swallowed it, and $global:Error holds more. Every copy
    # points (through TargetObject, the exception chain, Response.RequestMessage) at the one
    # HttpRequestMessage the call built, and that message carries "Authorization: Bearer <token>".
    # Remove-OERErrorRecord clears the header ON that shared instance, which is the only thing that
    # reaches the copies already published. So the proof is not "which records are in the
    # collection" but "no request instance reachable from any record has the header".
    #
    # THE REAL WRAPPER RUNS. Invoke-OERGraphRequest, Convert-GraphHttpException and
    # Remove-OERErrorRecord are the module's own; only the raw SDK call is mocked (a Pester mock
    # of Invoke-MgGraphRequest, the true transport boundary), and it fails the way the SDK does for
    # a 404: an ErrorRecord whose TargetObject is the request, wrapping an exception that carries
    # the response, whose RequestMessage is that same request. Initialize-OERAuth is mocked.
    #
    # NON-VACUITY AND THE CONTROL. "None has the header" is also true of a walk that reaches
    # nothing. So (1) the walk must reach at least one request instance, and (2) the same call with
    # Remove-OERErrorRecord mocked to a no-op must show the walk DOES find the header. The control
    # is the proof that assertion (the clean walk) can fail.
    BeforeAll {
        if (-not ('OERCatalogBearerFixture.SdkHttpException' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Net.Http;
namespace OERCatalogBearerFixture {
    public class SdkHttpException : Exception {
        public HttpResponseMessage Response { get; private set; }
        public SdkHttpException(string message, HttpResponseMessage response) : base(message) {
            Response = response;
        }
    }
}
'@
        }

        # The SDK-shaped 404: a fresh request carrying the bearer on every call, one shared instance
        # behind both TargetObject and Response.RequestMessage. The value carries NOT-A-REAL-TOKEN.
        function New-CatalogBearerNotFoundRecord {
            $Request = [System.Net.Http.HttpRequestMessage]::new(
                'GET', 'https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs/cat-missing')
            $Request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', 'NOT-A-REAL-TOKEN')
            $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::NotFound)
            $Response.Content = [System.Net.Http.StringContent]::new(
                '{"error":{"code":"Request_ResourceNotFound","message":"Resource cat-missing does not exist."}}')
            $Response.RequestMessage = $Request
            $Exception = [OERCatalogBearerFixture.SdkHttpException]::new(
                'Response status code does not indicate success: 404 (Not Found).', $Response)
            [System.Management.Automation.ErrorRecord]::new(
                $Exception, 'HttpResponseException',
                [System.Management.Automation.ErrorCategory]::InvalidOperation, $Request)
        }

        # One walker for every record in a collection: records, their Exception chains (InnerException
        # and an aggregate's InnerExceptions), Response / RequestMessage / Request members, and
        # TargetObject. Returns the DISTINCT HttpRequestMessage instances reached, by reference.
        function Get-ReachedRequestInstance {
            param($Record)
            $Found = [System.Collections.Generic.List[object]]::new()
            $Seen = [System.Collections.Generic.List[object]]::new()
            $Pending = [System.Collections.Generic.Queue[object]]::new()
            foreach ($Item in @($Record)) { if ($null -ne $Item) { $Pending.Enqueue($Item) } }
            $Visited = 0
            while ($Pending.Count -gt 0 -and $Visited -lt 5000) {
                $Node = $Pending.Dequeue()
                if ($null -eq $Node) { continue }
                $Known = $false
                foreach ($S in $Seen) { if ([object]::ReferenceEquals($S, $Node)) { $Known = $true; break } }
                if ($Known) { continue }
                $Seen.Add($Node)
                $Visited++
                if ($Node -is [System.Net.Http.HttpRequestMessage]) { $Found.Add($Node); continue }
                if ($Node -is [System.Net.Http.HttpResponseMessage]) {
                    if ($null -ne $Node.RequestMessage) { $Pending.Enqueue($Node.RequestMessage) }
                    continue
                }
                if ($Node -is [System.Management.Automation.ErrorRecord]) {
                    $Pending.Enqueue($Node.Exception)
                    $Pending.Enqueue($Node.TargetObject)
                    continue
                }
                if ($Node -is [System.Exception]) {
                    $Pending.Enqueue($Node.InnerException)
                    $Inners = $Node.PSObject.Properties['InnerExceptions']
                    if ($null -ne $Inners) { foreach ($I in @($Inners.Value)) { $Pending.Enqueue($I) } }
                }
                # An exception, or a wrapper object standing between a record and the request.
                foreach ($MemberName in @('Response', 'RequestMessage', 'Request')) {
                    try {
                        $Member = $Node.PSObject.Properties[$MemberName]
                        if ($null -ne $Member -and $null -ne $Member.Value) { $Pending.Enqueue($Member.Value) }
                    } catch { $null = $PSItem }
                }
            }
            , @($Found)
        }

        function Test-RequestHasAuthorization {
            param([System.Net.Http.HttpRequestMessage]$Request)
            ($null -ne $Request.Headers.Authorization) -or $Request.Headers.Contains('Authorization')
        }

        # The Graph read the cmdlet makes for an id that does not exist, run through the real wrapper.
        # Returns the -ErrorVariable collection; $global:Error is read by the caller afterwards.
        function Invoke-CatalogNotFoundRead {
            $global:Error.Clear()
            $EV = $null
            $Result = Get-OERCatalog -Id 'cat-missing' -ErrorAction SilentlyContinue -ErrorVariable EV
            [pscustomobject]@{ Result = $Result; EV = @($EV) }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            throw (New-CatalogBearerNotFoundRecord)
        }
        $global:Error.Clear()
    }

    AfterEach {
        # Leave no failure record (and no request) behind for the next test of this process.
        $global:Error.Clear()
    }

    It 'leaves no request instance reachable from -ErrorVariable or $global:Error with an Authorization header' {
        $Run = Invoke-CatalogNotFoundRead
        $Run.Result | Should -BeNullOrEmpty

        # The real wrapper ran: the raw SDK call was made exactly once and the cmdlet wrote its own
        # record (cmdlet-qualified id; the bare code is also deposited by the engine).
        Should -Invoke -ModuleName $script:moduleName Invoke-MgGraphRequest -Times 1 -Exactly
        @($Run.EV | Where-Object { $_.FullyQualifiedErrorId -eq 'Request_ResourceNotFound,Get-OERCatalog' }).Count |
            Should -Be 1

        $Requests = @((Get-ReachedRequestInstance -Record @(@($Run.EV) + @($global:Error)))[0])

        # Non-vacuity: the walk reached the request at all.
        $Requests.Count | Should -BeGreaterOrEqual 1 -Because 'a walk that reaches no request proves nothing'
        foreach ($Request in $Requests) {
            $Request | Should -BeOfType ([System.Net.Http.HttpRequestMessage])
            $Request.Headers.Authorization | Should -BeNullOrEmpty
            $Request.Headers.Contains('Authorization') | Should -BeFalse
            Test-RequestHasAuthorization -Request $Request | Should -BeFalse
        }

        # The counts a live run is compared with (shown in the run output).
        Write-Host ('BEARER-WALK EV records: {0}; types: {1}; $global:Error records: {2}; distinct requests: {3}' -f $Run.EV.Count,
            (($Run.EV | ForEach-Object { if ($_.Exception) { '{0}/{1}' -f $_.GetType().Name, $_.Exception.GetType().Name } else { $_.GetType().Name } } | Group-Object | ForEach-Object { '{0}x{1}' -f $_.Name, $_.Count }) -join ', '),
            @($global:Error).Count, $Requests.Count)
    }

    It 'control: with the scrub mocked to a no-op, the same walk finds the header' {
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }

        $Run = Invoke-CatalogNotFoundRead
        $Run.Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1

        $Requests = @((Get-ReachedRequestInstance -Record @(@($Run.EV) + @($global:Error)))[0])
        $Requests.Count | Should -BeGreaterOrEqual 1 -Because 'the control must reach the request to prove anything'
        $WithHeader = @($Requests | Where-Object { Test-RequestHasAuthorization -Request $_ })
        $WithHeader.Count | Should -BeGreaterOrEqual 1 -Because 'without the scrub the very walk used above has to find the bearer header'
        @($WithHeader | Where-Object { $_.Headers.Authorization.Parameter -eq 'NOT-A-REAL-TOKEN' }).Count |
            Should -BeGreaterOrEqual 1
    }
}
