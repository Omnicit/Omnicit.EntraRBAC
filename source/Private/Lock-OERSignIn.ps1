function Lock-OERSignIn {
    <#
    .SYNOPSIS
    Latches the command that called Initialize-OERAuth, so the module sends nothing for it until its
    sign-in succeeds.

    .DESCRIPTION
    Called only by Initialize-OERAuth, directly after its BL-74 check. It finds the invocation of the
    command that called Initialize-OERAuth -- the first frame of the call stack, after this function's
    own frame and Initialize-OERAuth's, that carries an invocation -- records it in the module's sign-in
    latch, and returns it. Initialize-OERAuth hands that invocation to Unlock-OERSignIn when the sign-in
    succeeds; every refusal, terminating error and early return leaves it latched -- except the BL-74
    refusal before this call, which latches nothing of its own. Both transports then refuse
    every request that command makes: Get-OERSignInRefusal finds it on the call stack and the request
    is refused with SignInRefused -- except that the Graph wrapper's session gate, which comes first,
    still reports a changed session as GraphSessionChanged.

    The latch is keyed on the calling command's invocation rather than held as one module-wide value,
    since a nested command or a pipeline neighbour signs in on its own: its success must release only
    its own entry, never the refused command's. The table ($script:_OERSignInLatch, created here on
    first use) is a ConditionalWeakTable and stores only the boolean $true. Its keys are the commands'
    own invocation objects, held weakly, so the table keeps no command alive, and used only for their
    identity: the decision is a lookup by reference and never reads a key, although each one carries
    its command's bound parameters, a tenant among them.

    .EXAMPLE
    $SignInCaller = Lock-OERSignIn

    Latches the command that called Initialize-OERAuth and keeps its invocation for Unlock-OERSignIn.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.InvocationInfo])]
    param()

    # Frame 0 is this function and frame 1 is Initialize-OERAuth; the caller is the next frame that
    # carries an invocation. A frame's invocation is the very object $MyInvocation holds in that
    # command (begin, process and end alike), which is what Get-OERSignInRefusal looks up.
    # Module-qualified, so a function named Get-PSCallStack defined in the session cannot turn the
    # latch off.
    $Stack = @(Microsoft.PowerShell.Utility\Get-PSCallStack)
    $Caller = $null
    for ($Index = 2; $Index -lt $Stack.Count; $Index++) {
        if ($null -ne $Stack[$Index].InvocationInfo) {
            $Caller = $Stack[$Index].InvocationInfo
            break
        }
    }

    if ($null -eq $script:_OERSignInLatch) {
        $script:_OERSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
    }
    $script:_OERSignInLatch.AddOrUpdate($Caller, $true)
    $Caller
}
