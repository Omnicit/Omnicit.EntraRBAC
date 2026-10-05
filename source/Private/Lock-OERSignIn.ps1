function Lock-OERSignIn {
    <#
    .SYNOPSIS
    Latches the command that called Initialize-OERAuth, so the module sends nothing for it until its
    sign-in succeeds.

    .DESCRIPTION
    Called only by Initialize-OERAuth, as its first statement. It finds the invocation of the command
    that called Initialize-OERAuth -- the first frame of the call stack, after this function's own frame
    and Initialize-OERAuth's, that carries an invocation -- records it in the module's sign-in latch, and
    returns it. Initialize-OERAuth hands that invocation to Unlock-OERSignIn when the sign-in succeeds;
    every refusal, terminating error and early return leaves it latched, and Get-OERSignInRefusal then
    finds it on the call stack of every request that command makes.

    The latch is keyed on the calling command's invocation rather than held as one module-wide value,
    since a nested command or a pipeline neighbour signs in on its own: its success must release only
    its own entry, never the refused command's. The table ($script:_OERSignInLatch, created here on
    first use) is a ConditionalWeakTable, so it holds its keys weakly and never keeps a finished
    command alive, and every value in it is the boolean $true. It holds no token and no tenant value.

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
    $Stack = @(Get-PSCallStack)
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
