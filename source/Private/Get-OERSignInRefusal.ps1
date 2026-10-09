function Get-OERSignInRefusal {
    <#
    .SYNOPSIS
    Returns the name of the command whose refused sign-in this request belongs to, or nothing.

    .DESCRIPTION
    Walks the call stack from the innermost frame outwards and returns, for the first frame whose
    invocation the module's sign-in latch holds, the name of that command -- or 'a script block' when
    the held frame carries no command name. Returns nothing when no frame on the stack is held, and
    returns at once, without reading the call stack, when the latch table was never created: unit tests
    that mock Initialize-OERAuth never create one.

    Initialize-OERAuth latches the command that called it at entry and releases it only when its
    sign-in succeeds (Lock-OERSignIn, Unlock-OERSignIn). A command whose sign-in was refused carries on
    past the refusal when no try is active up the call stack. Both transports call this function
    before every request -- Invoke-OERGraphRequest after its session gate, which still refuses a
    changed session as GraphSessionChanged and so comes first -- so every request such a command
    makes, directly or through a command it calls, that reaches this check finds its frame here. A
    command that has finished is on no call stack, so the latch does not refuse the command after it.

    The latched command is the one that called Initialize-OERAuth directly. Inside a transport's own
    sign-in (its renewal before a request, the Graph claims step-up, the token-rejected retry of
    either transport) that is the transport's nested function, Invoke-GraphSingle or
    Invoke-ArmCallWithRefresh, so the name returned for the request that follows such a sign-in's
    failure is an internal function's.

    With -OutsideCaller, which only Initialize-OERAuth passes, for its BL-74 check before it latches
    its own caller, the walk starts after the command that called Initialize-OERAuth: frame 0 is this
    function, frame 1 Initialize-OERAuth, and the caller is the first frame from index 2 that carries
    an invocation -- the frame Lock-OERSignIn latches. Only a command outside that caller counts, so a
    command whose own sign-in was refused earlier in the same invocation may still sign in again,
    while a command it calls may not. The transports never pass it.

    .PARAMETER OutsideCaller
    Start the walk after the command that called Initialize-OERAuth, so only a command outside that
    caller counts. Initialize-OERAuth only, for its BL-74 check; the transports never pass it.

    .EXAMPLE
    $Refused = Get-OERSignInRefusal
    if ($Refused) { throw (New-OERSignInRefusedError -Command $Refused) }

    Refuses a request made on behalf of a command whose sign-in was refused.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Initialize-OERAuth only, for its BL-74 check before it latches its caller: start the walk
        # after the command that called Initialize-OERAuth -- the first frame after this function's and
        # Initialize-OERAuth's own that carries an invocation, the frame Lock-OERSignIn latches -- so
        # only a command OUTSIDE that caller counts. The transports never pass it.
        [switch]$OutsideCaller
    )

    if ($null -eq $script:_OERSignInLatch) {
        return
    }
    $Held = $null
    # Module-qualified, so a function named Get-PSCallStack defined in the session cannot turn the
    # latch off.
    $Stack = @(Microsoft.PowerShell.Utility\Get-PSCallStack)
    $Start = 0
    if ($OutsideCaller) {
        $Start = $Stack.Count
        for ($Index = 2; $Index -lt $Stack.Count; $Index++) {
            if ($null -ne $Stack[$Index].InvocationInfo) {
                $Start = $Index + 1
                break
            }
        }
    }
    for ($Index = $Start; $Index -lt $Stack.Count; $Index++) {
        $Inv = $Stack[$Index].InvocationInfo
        if ($null -eq $Inv) {
            continue
        }
        if ($script:_OERSignInLatch.TryGetValue($Inv, [ref]$Held)) {
            [string]$Name = $Inv.MyCommand.Name
            if (-not $Name) {
                $Name = 'a script block'
            }
            return $Name
        }
    }
}
