function Unlock-OERSignIn {
    <#
    .SYNOPSIS
    Releases the sign-in latch of one command, after its sign-in succeeded.

    .DESCRIPTION
    Called only by Initialize-OERAuth, where a sign-in succeeded: at its cached return, and as the last
    statement of a new connection that went the whole way. It removes the given invocation -- the one
    Lock-OERSignIn returned at entry -- from the module's sign-in latch, and nothing else, so a nested
    command's or a pipeline neighbour's success never releases another command that is still latched.
    It does nothing when the latch table has not been created, and creates none.

    .PARAMETER Invocation
    The invocation of the command whose sign-in succeeded, exactly as Lock-OERSignIn returned it at the
    entry of the same Initialize-OERAuth call.

    .EXAMPLE
    Unlock-OERSignIn -Invocation $SignInCaller

    Releases the command Lock-OERSignIn latched at the entry of this Initialize-OERAuth call.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.InvocationInfo]$Invocation
    )

    if ($null -ne $script:_OERSignInLatch) {
        $null = $script:_OERSignInLatch.Remove($Invocation)
    }
}
