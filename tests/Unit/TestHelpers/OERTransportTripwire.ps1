# Test helper -- NOT a Pester file (no *.Tests.ps1 suffix, so Pester discovery ignores it).
#
# THE TRANSPORT TRIPWIRE (Sprint 8 step 4, decision A13). No unit test may reach a tenant or the
# network. Mocking Initialize-OERAuth is not enough: with no auth state Invoke-OERArmRequest falls
# back to https://management.azure.com and sends a real, unauthenticated Invoke-WebRequest. So every
# unit test file installs, in its root BeforeAll and AFTER Import-Module, a GLOBAL replacement for
# each of the six commands through which module code reaches the transport, and checks and removes
# them in its root AfterAll. tests/QA/testhygiene.tests.ps1 proves every file does.
#
# Why this works: source/ never module-qualifies these calls, and a function outranks a cmdlet in
# command resolution, so module code resolves the global replacement. A Pester Mock -ModuleName is
# an alias in the module's script scope and outranks both, so every existing mock keeps working.
#
# Why record AND throw: a throw alone is not enough, since the module's own catch blocks turn it into
# a WriteError or a Failed row that a test may never look at. The record is what the AfterAll check
# reads. It holds parameter NAMES only -- never a value, which may be a secret or a token.
#
# Why built from the real cmdlet's metadata: Pester builds a mock's parameter block from the command
# it resolves, which is now this function, so the function must have exactly the cmdlet's parameters
# and no dynamicparam block (a Pester mock of a dynamicparam proxy fails; see
# docs/development/rationale.md#bearer-scrub-tests). None of the six declares dynamic parameters
# (measured 2026-10-05; Invoke-RestMethod, added 2026-10-06 for the tenant lookup, measured on
# PowerShell 7.6.6); New-OERTransportTripwireDefinition refuses one that starts to.
#
# Not a source/ check and not a build step, on purpose (A13): a check in source/ would publish a
# test switch to the Gallery, and a build step would not cover a single Invoke-Pester run.

function Get-OERTransportTripwireName {
    <#
    .SYNOPSIS
    The six commands through which module code reaches a tenant or the network.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    'Get-AzToken'
    'Connect-MgGraph'
    'Disconnect-MgGraph'
    'Invoke-MgGraphRequest'
    'Invoke-WebRequest'
    'Invoke-RestMethod'
}

function Test-OERTransportTripwireFunction {
    <#
    .SYNOPSIS
    True when Command is a function carrying the tripwire marker.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object]$Command
    )
    ($Command -is [System.Management.Automation.FunctionInfo]) -and
    $Command.ScriptBlock.ToString().Contains('OER-TRANSPORT-TRIPWIRE')
}

function New-OERTransportTripwireDefinition {
    <#
    .SYNOPSIS
    Builds the text of each replacement function from the real cmdlet's metadata.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    $Definitions = [ordered]@{}
    foreach ($Name in Get-OERTransportTripwireName) {
        $Cmdlets = @(Get-Command -Name $Name -CommandType Cmdlet -ErrorAction Stop)
        if ($Cmdlets.Count -ne 1) {
            throw ('Transport tripwire: expected exactly one cmdlet named {0}, found {1}. Import the module first.' -f $Name, $Cmdlets.Count)
        }
        $Cmdlet = $Cmdlets[0]
        if ([System.Management.Automation.IDynamicParameters].IsAssignableFrom($Cmdlet.ImplementingType)) {
            throw ('Transport tripwire: {0} declares dynamic parameters, which a Pester mock of a replacement function cannot evaluate. Measure again before extending the tripwire.' -f $Name)
        }
        $Metadata = [System.Management.Automation.CommandMetadata]::new($Cmdlet)
        $Binding = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Metadata)
        $ParamBlock = [System.Management.Automation.ProxyCommand]::GetParamBlock($Metadata)
        $Definitions[$Name] = @"
$Binding
param($ParamBlock)
end {
    # OER-TRANSPORT-TRIPWIRE
    `$Caller = @(Get-PSCallStack)[1]
    if (`$null -ne `$global:OERTransportTripwireHits) {
        `$null = `$global:OERTransportTripwireHits.Add([pscustomobject]@{
                Command    = '$Name'
                Caller     = if (`$Caller) { ('{0}:{1}' -f `$Caller.ScriptName, `$Caller.ScriptLineNumber) } else { '' }
                Parameters = (@(`$PSBoundParameters.Keys) -join ',')
            })
    }
    throw [System.InvalidOperationException]::new('OER transport tripwire: a unit test reached the real $Name. Mock it, or the module function that calls it, with Mock -ModuleName Omnicit.EntraRBAC.')
}
"@
    }
    $Definitions
}

function Install-OERTransportTripwire {
    <#
    .SYNOPSIS
    Defines the six global replacements and starts an empty hit list. Call it after Import-Module.
    #>
    [CmdletBinding()]
    param()
    $Definitions = New-OERTransportTripwireDefinition
    $global:OERTransportTripwireHits = [System.Collections.Generic.List[object]]::new()
    $global:OERTransportTripwireDefinitions = $Definitions
    foreach ($Entry in $Definitions.GetEnumerator()) {
        Set-Item -Path ('function:global:' + $Entry.Key) -Value ([scriptblock]::Create($Entry.Value))
    }
    foreach ($Name in $Definitions.Keys) {
        if (-not (Test-OERTransportTripwireFunction -Command (Get-Command -Name $Name -CommandType Function -ErrorAction Ignore))) {
            throw ('Transport tripwire: {0} does not resolve to its replacement after installation.' -f $Name)
        }
    }
}

function Assert-OERTransportTripwire {
    <#
    .SYNOPSIS
    Throws when a unit test reached the transport, or when a replacement no longer resolves.
    #>
    [CmdletBinding()]
    param()
    $Problems = [System.Collections.Generic.List[string]]::new()
    foreach ($Hit in @($global:OERTransportTripwireHits)) {
        if ($null -eq $Hit) { continue }
        $Problems.Add(('reached {0} from {1} (parameters: {2})' -f $Hit.Command, $Hit.Caller, $Hit.Parameters))
    }
    $Module = Get-Module -Name Omnicit.EntraRBAC | Select-Object -First 1
    foreach ($Name in Get-OERTransportTripwireName) {
        $Resolved = if ($Module) {
            & $Module { param($N) Get-Command -Name $N -CommandType Function -ErrorAction Ignore } $Name
        } else {
            Get-Command -Name $Name -CommandType Function -ErrorAction Ignore
        }
        if (-not (Test-OERTransportTripwireFunction -Command $Resolved)) {
            $Problems.Add(('{0} no longer resolves to the tripwire from the module scope' -f $Name))
        }
    }
    if ($Problems.Count -gt 0) {
        throw ('OER transport tripwire: {0}' -f ($Problems -join '; '))
    }
}

function Uninstall-OERTransportTripwire {
    <#
    .SYNOPSIS
    Removes the six global replacements and the definitions.
    #>
    [CmdletBinding()]
    param()
    # Remove-Item honours no scope qualifier on the function: drive: 'function:global:X' removes
    # nothing and raises no error, with or without -Force (measured 2026-10-05, PowerShell 7.6). An
    # unqualified path removes the NEAREST definition up the scope chain, which from here is the
    # global replacement -- so a name is removed only while its nearest definition IS a replacement,
    # never a function a test defined. The check below then reads from here AND from the module's
    # scope, so a replacement left behind is reported, not silently kept.
    foreach ($Name in Get-OERTransportTripwireName) {
        if (Test-OERTransportTripwireFunction -Command (Get-Command -Name $Name -CommandType Function -ErrorAction Ignore)) {
            Remove-Item -Path ('function:' + $Name) -ErrorAction SilentlyContinue
        }
    }
    $global:OERTransportTripwireDefinitions = $null
    $Module = Get-Module -Name Omnicit.EntraRBAC | Select-Object -First 1
    $Left = @(Get-OERTransportTripwireName | Where-Object {
            (Test-OERTransportTripwireFunction -Command (Get-Command -Name $_ -CommandType Function -ErrorAction Ignore)) -or
            ($Module -and (Test-OERTransportTripwireFunction -Command (& $Module { param($N) Get-Command -Name $N -CommandType Function -ErrorAction Ignore } $_)))
        })
    if ($Left.Count -gt 0) {
        throw ('OER transport tripwire: still defined after uninstall: {0}' -f ($Left -join ', '))
    }
}

function Install-OERTransportTripwireInRunspace {
    <#
    .SYNOPSIS
    Installs the parent's replacements in a second runspace and shares the parent's hit list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.Runspace]$Runspace
    )
    if ($null -eq $global:OERTransportTripwireDefinitions -or $null -eq $global:OERTransportTripwireHits) {
        throw 'OER transport tripwire: refusing to run module code in a second runspace without the tripwire. Call Install-OERTransportTripwire first (tests/Unit/TestHelpers/OERTransportTripwire.ps1).'
    }
    $Runspace.SessionStateProxy.SetVariable('OERTransportTripwireHits', $global:OERTransportTripwireHits)
    $Runspace.SessionStateProxy.SetVariable('OERTransportTripwireDefinitions', $global:OERTransportTripwireDefinitions)
    $Shell = [powershell]::Create()
    try {
        $Shell.Runspace = $Runspace
        $null = $Shell.AddScript({
                foreach ($Entry in $global:OERTransportTripwireDefinitions.GetEnumerator()) {
                    Set-Item -Path ('function:global:' + $Entry.Key) -Value ([scriptblock]::Create($Entry.Value))
                }
            }.ToString())
        $null = $Shell.Invoke()
        if ($Shell.HadErrors) {
            throw ('OER transport tripwire: installation in the second runspace failed: {0}' -f (($Shell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '))
        }
    } finally {
        $Shell.Dispose()
    }
}

function Test-OERTransportTripwireInRunspace {
    <#
    .SYNOPSIS
    After a scenario, records a hit in the shared list for every name that no longer resolves there.
    .DESCRIPTION
    Throws when the check itself raised an error in that runspace. A scenario that left the
    runspace's definitions or hit list unreadable would otherwise make the check record nothing
    while reporting success -- a replacement removed there would then go unnoticed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.Runspace]$Runspace
    )
    $Shell = [powershell]::Create()
    try {
        $Shell.Runspace = $Runspace
        $null = $Shell.AddScript({
                $Module = Get-Module -Name Omnicit.EntraRBAC | Select-Object -First 1
                foreach ($Name in @($global:OERTransportTripwireDefinitions.Keys)) {
                    $Resolved = if ($Module) {
                        & $Module { param($N) Get-Command -Name $N -CommandType Function -ErrorAction Ignore } $Name
                    } else {
                        Get-Command -Name $Name -CommandType Function -ErrorAction Ignore
                    }
                    $IsTripwire = ($Resolved -is [System.Management.Automation.FunctionInfo]) -and $Resolved.ScriptBlock.ToString().Contains('OER-TRANSPORT-TRIPWIRE')
                    if (-not $IsTripwire) {
                        $null = $global:OERTransportTripwireHits.Add([pscustomobject]@{
                                Command    = $Name
                                Caller     = 'answering runspace: no longer resolves to the tripwire'
                                Parameters = ''
                            })
                    }
                }
            }.ToString())
        $null = $Shell.Invoke()
        if ($Shell.HadErrors) {
            throw ('OER transport tripwire: the check in the second runspace failed: {0}' -f (($Shell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '))
        }
    } finally {
        $Shell.Dispose()
    }
}
