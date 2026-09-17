function Get-OERRequiredScope {
    <#
    .SYNOPSIS
    Returns the Microsoft Graph permissions and Azure RBAC roles one or more OER cmdlets need.

    .DESCRIPTION
    Reads the reviewed per-cmdlet permission table that ships with the module and returns it, either
    in full or filtered to the cmdlets you name. This is the list to hand to whoever grants admin
    consent in a new tenant: it is derived per cmdlet rather than per functional area, because
    Microsoft Graph grants permissions by the resource a call touches and a functional area is not a
    permission boundary. The three administrative-unit scoped-role cmdlets, for instance, write
    directory role memberships and need a role-management permission, not an administrative-unit one.

    Each entry is TRANSITIVE. It covers the cmdlet''s own calls and every call its internal helpers
    make on its behalf, including the directory reads behind friendly-name parameters such as -User,
    -Group and -ServicePrincipal. Consenting to the listed permissions is therefore enough to run the
    cmdlet in all of its parameter forms; where a permission is needed only for one form, Note says so.

    Transport tells you which transports a cmdlet reaches, so an empty GraphScope is never ambiguous:
    Graph, Arm, GraphAndArm, or None for a cmdlet that touches neither (Tenant Profile file
    operations, in-memory builders, and offline validation).

    Directory reads can be consented individually or collectively. Where an entry lists any
    combination of User.ReadBasic.All, Group.Read.All and Application.Read.All, a single
    Directory.Read.All covers all three; the narrower permissions are listed because the module
    prefers least privilege.

    The default table view shows Cmdlet, Transport, GraphScope and AzureRole. Two more properties
    are on every object and worth reading before you act on one: Note carries the conditional
    requirements and caveats, and Verified records whether the values were confirmed against a
    published Microsoft Learn permissions table. Pipe to Format-List to see them.

    This cmdlet reads a static table. It never authenticates and never calls a tenant, so it works
    before Connect-OER and against no tenant at all.

    .PARAMETER Cmdlet
    One or more exported cmdlet names to report on. Wildcards are supported, so Get-OER* returns the
    consent list for every read cmdlet. Accepts pipeline input by value and by property name, which
    makes Get-Command -Module Omnicit.EntraRBAC | Get-OERRequiredScope work directly. Omit the
    parameter to return the whole table. A name or pattern matching nothing produces a
    non-terminating error and the remaining values are still processed.

    .PARAMETER Unique
    Return a single summary object holding the deduplicated union of the Graph permissions and Azure
    roles across every matched cmdlet, instead of one object per cmdlet. This is the form to paste
    into an admin-consent request for a whole workflow.

    .EXAMPLE
    Get-OERRequiredScope -Cmdlet New-OERGroup, Add-OERAdministrativeUnitScopedRole

    Returns one entry per named cmdlet, showing the Graph permissions each one needs.

    .EXAMPLE
    Get-OERRequiredScope

    Returns the whole table, one entry per exported cmdlet.

    .EXAMPLE
    Get-OERRequiredScope -Cmdlet Get-OER* -Unique

    Returns the single deduplicated consent list covering every read cmdlet in the module.

    .EXAMPLE
    (Get-OERRequiredScope -Cmdlet Invoke-OERStructure).GraphScope -join ' '

    Produces a space-separated permission list ready to paste into an admin-consent request.

    .EXAMPLE
    Get-OERRequiredScope -Cmdlet Add-OERCatalogResource | Format-List

    Shows the Note and Verified properties as well, which the default table view leaves out. This
    cmdlet's note records that an app-only caller onboarding a SharePoint site needs an extra
    permission beyond the ones listed.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]]$Cmdlet,

        [Parameter()]
        [switch]$Unique
    )

    begin {
        $Table = @(Get-OERRequiredScopeMap)
        $Matched = [System.Collections.Generic.List[object]]::new()
        $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        <#
            ExpectingInput is true whenever this command sits on the receiving end of a pipeline,
            even when that pipeline turns out to be empty. Without it, an empty upstream would fall
            through to "no filter supplied" and return the whole table instead of nothing.
        #>
        $Filtered = $MyInvocation.ExpectingInput -or $PSBoundParameters.ContainsKey('Cmdlet')
    }

    process {
        if (-not $PSBoundParameters.ContainsKey('Cmdlet')) {
            return
        }

        foreach ($Pattern in $Cmdlet) {
            if ([string]::IsNullOrWhiteSpace($Pattern)) {
                Write-CmdletError -Message ([System.Exception]::new(
                        'A cmdlet name cannot be empty.')) -ErrorId 'CmdletNotFound' `
                    -Category ObjectNotFound -TargetObject $Pattern -Cmdlet $PSCmdlet
                continue
            }

            $Hits = @($Table | Where-Object { $_.Cmdlet -like $Pattern })

            if (-not $Hits.Count) {
                Write-CmdletError -Message ([System.Exception]::new((
                            "No exported Omnicit.EntraRBAC cmdlet matches '{0}'." -f $Pattern))) `
                    -ErrorId 'CmdletNotFound' -Category ObjectNotFound -TargetObject $Pattern `
                    -Details 'Run Get-OERRequiredScope with no parameters to list every cmdlet in the table.' `
                    -Cmdlet $PSCmdlet
                continue
            }

            foreach ($Hit in $Hits) {
                if ($Seen.Add($Hit.Cmdlet)) {
                    $Matched.Add($Hit)
                }
            }
        }
    }

    end {
        <#
            Ordering: the unfiltered table comes out alphabetically, because that is how the map
            stores it. A filtered result follows the order the names were asked for, which is the
            more useful answer to an explicit request. What matters for diffing one consent list
            against another is the -Unique arrays below, and those are sorted.
        #>
        $Result = if ($Filtered) { @($Matched) } else { $Table }

        if ($Unique) {
            $Summary = [PSCustomObject]@{
                GraphScope  = [string[]]@($Result | ForEach-Object { $_.GraphScope } | Where-Object { $_ } | Sort-Object -Unique)
                AzureRole   = [string[]]@($Result | ForEach-Object { $_.AzureRole } | Where-Object { $_ } | Sort-Object -Unique)
                Cmdlet      = [string[]]@($Result | ForEach-Object { $_.Cmdlet })
                CmdletCount = @($Result).Count
            }
            $Summary.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequiredScopeSummary')
            $Summary
            return
        }

        foreach ($Entry in $Result) {
            $Out = [PSCustomObject]@{
                Cmdlet     = $Entry.Cmdlet
                Transport  = $Entry.Transport
                GraphScope = $Entry.GraphScope
                AzureRole  = $Entry.AzureRole
                Verified   = $Entry.Verified
                Note       = $Entry.Note
            }
            $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequiredScope')
            $Out
        }
    }
}
