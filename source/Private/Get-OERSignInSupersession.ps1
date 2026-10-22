function Get-OERSignInSupersession {
    <#
    .SYNOPSIS
    Returns the name of a command on the call stack whose sign-in another command has since replaced,
    or nothing.

    .DESCRIPTION
    Reads the identity the module's state carries now (Get-OERSignInIdentity) once, then walks the call
    stack from the innermost frame outwards and returns, for the first frame whose invocation the
    module's sign-in memory holds with a different identity, the name of that command -- or 'a script
    block' when that frame carries no command name. The comparison is PowerShell's case-insensitive
    -eq, and no state at all differs from every remembered identity. A frame the memory does not hold
    is not compared: unit tests that mock Initialize-OERAuth remember nothing. Returns nothing when no
    frame differs, and returns at once, without reading the call stack, when the memory table was never
    created.

    Initialize-OERAuth remembers, for each command whose sign-in succeeded, the identity it signed in
    as (Register-OERSignInIdentity). In a pipeline every begin block runs first, so in
    New-OERGroup -TenantId A ... | Add-OERGroupMember -TenantId B the second sign-in switches the state
    to B before New-OERGroup's process block sends anything; and a nested cmdlet that inherits the
    session sends under whatever a later pipeline command switched it to. Both transports call this
    function before every request and refuse it with SignInSuperseded when it returns a name. The walk
    goes on past a frame whose memory equals the state, since an outer command can differ while the
    command nested in it does not.

    The name returned is that of a command whose frame is on the call stack, which is not always the
    command making the request: a downstream pipeline command processes each object inside the
    upstream command's output call, so for a request it makes there the frame found can be the upstream
    command's (Up | Down, Up | ForEach-Object { Inner }).

    With -OutsideCaller, which only Initialize-OERAuth passes, for its BL-91 check before it latches
    its own caller, the walk starts after the command that called Initialize-OERAuth: frame 0 is this
    function, frame 1 Initialize-OERAuth, and the caller is the first frame from index 2 that carries
    an invocation -- the frame Lock-OERSignIn latches. Only a command outside that caller counts, so a
    command whose own remembered identity is another than the state's (it signed in before, and a
    later command switched the state) may still sign in again, and its memory is replaced on success,
    while a command it calls may not. The transports never pass it.

    .PARAMETER OutsideCaller
    Start the walk after the command that called Initialize-OERAuth, so only a command outside that
    caller counts. Initialize-OERAuth only, for its BL-91 check; the transports never pass it.

    .EXAMPLE
    $Superseded = Get-OERSignInSupersession
    if ($Superseded) { throw (New-OERSignInSupersededError -Command $Superseded) }

    Refuses a request made while a command whose sign-in another command has since replaced runs.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Initialize-OERAuth only, for its BL-91 check before it latches its caller: start the walk
        # after the command that called Initialize-OERAuth -- the first frame after this function's and
        # Initialize-OERAuth's own that carries an invocation, the frame Lock-OERSignIn latches -- so
        # only a command OUTSIDE that caller counts. The transports never pass it.
        [switch]$OutsideCaller
    )

    if ($null -eq $script:_OERSignInIdentity) {
        return
    }
    $Current = Get-OERSignInIdentity
    $Remembered = $null
    # Module-qualified, so a function named Get-PSCallStack defined in the session cannot turn the
    # check off.
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
        if (-not $script:_OERSignInIdentity.TryGetValue($Inv, [ref]$Remembered)) {
            continue
        }
        # A remembered identity is always a string, and a string is never -eq to $null, so no current
        # identity differs from every remembered one.
        if ($Remembered -eq $Current) {
            continue
        }
        [string]$Name = $Inv.MyCommand.Name
        if (-not $Name) {
            $Name = 'a script block'
        }
        return $Name
    }
}
