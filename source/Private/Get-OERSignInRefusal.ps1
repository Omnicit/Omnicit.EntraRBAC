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
    past the refusal when no try is active up the call stack, so every request it makes, directly or
    through a command it calls, finds its frame here. A command that has finished is on no call stack,
    so the next command is not refused.

    .EXAMPLE
    $Refused = Get-OERSignInRefusal
    if ($Refused) { throw (New-OERSignInRefusedError -Command $Refused) }

    Refuses a request made on behalf of a command whose sign-in was refused.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($null -eq $script:_OERSignInLatch) {
        return
    }
    $Held = $null
    foreach ($Frame in Get-PSCallStack) {
        $Inv = $Frame.InvocationInfo
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
