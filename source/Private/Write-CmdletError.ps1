using namespace System.Management.Automation
function Write-CmdletError {
    <#
    .SYNOPSIS
    Emits a structured ErrorRecord through the calling cmdlet's error channel.

    .DESCRIPTION
    Creates a System.Management.Automation.ErrorRecord from the supplied exception and dispatches
    it through the provided cmdlet context. By default the error is non-terminating (WriteError).
    Specify -Terminating to call ThrowTerminatingError instead for pipeline-terminating errors.

    Two parameter sets are available:

    * Message (default) -- builds a new ErrorRecord from a -Message exception. Use -InnerException
      to chain a caught exception as the InnerException of the new record.
    * ErrorRecord -- emits a pre-built ErrorRecord directly (pass-through). Use this when
      re-emitting a caught ErrorRecord without modification.

    .PARAMETER Message
    The Exception object used to construct the ErrorRecord. Its message and type are preserved in
    the resulting ErrorRecord. Use [System.Exception]::new('text') to wrap a plain string.

    .PARAMETER ErrorId
    A short, stable identifier assigned as the FullyQualifiedErrorId of the ErrorRecord.
    Use a descriptive PascalCase value such as RoleNotFound or RequestFailed.

    .PARAMETER Category
    The ErrorCategory that classifies the error type. Defaults to InvalidOperation.
    Accepts any System.Management.Automation.ErrorCategory enum value.

    .PARAMETER TargetObject
    The object the failed operation was working on -- a group id, an ARM scope, a tenant alias.
    Surfaced as ErrorRecord.TargetObject for the caller to inspect. Defaults to $null and callers
    pass it explicitly: a parameter default resolves $PSItem through the caller's dynamic scope, so
    it would otherwise bind the caught ErrorRecord when called from inside a catch block.

    .PARAMETER InnerException
    Optional Exception to chain as the InnerException of a new System.Exception wrapping
    the -Message text. Use in catch blocks to preserve the original exception:
        Write-CmdletError -Message ([Exception]::new("Friendly text")) -InnerException $PSItem.Exception

    .PARAMETER ErrorRecord
    A pre-built ErrorRecord to emit directly. When this parameter is supplied the -Message,
    -ErrorId, -Category, -TargetObject, -Details, and -InnerException parameters are ignored.

    .PARAMETER Cmdlet
    The PSCmdlet instance used to emit the error record. Supply the caller's $PSCmdlet so errors
    are attributed to the correct command.

    .PARAMETER Terminating
    Switch that promotes the error to a terminating error via ThrowTerminatingError. Without this
    switch the error is emitted as a non-terminating error via WriteError.

    .PARAMETER Details
    Optional plain-text detail message attached to the ErrorRecord as ErrorDetails.Message. Shown
    in some hosts in addition to the exception message for extra context.

    .EXAMPLE
    Write-CmdletError -Message ([System.Exception]::new('Role not found')) -ErrorId 'RoleNotFound' -Cmdlet $PSCmdlet

    Emits a non-terminating InvalidOperation ErrorRecord from within a cmdlet or advanced function.

    .EXAMPLE
    Write-CmdletError -Message ([System.Exception]::new("Auth failed: $($PSItem.Exception.Message)")) `
        -InnerException $PSItem.Exception -ErrorId 'AuthFailed' -Category AuthenticationError `
        -Cmdlet $PSCmdlet -Terminating

    Builds a chained exception and emits a terminating error.

    .EXAMPLE
    Write-CmdletError -ErrorRecord $PSItem -Cmdlet $PSCmdlet

    Re-emits a caught ErrorRecord unchanged as a non-terminating error.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Message')]
    param(
        [Parameter(ParameterSetName = 'Message')]
        [Exception]$Message = 'An Error Occured in the cmdlet',

        [Parameter(ParameterSetName = 'Message')]
        [String]$ErrorId,

        [Parameter(ParameterSetName = 'Message')]
        [ErrorCategory]$Category = 'InvalidOperation',

        [Parameter(ParameterSetName = 'Message')]
        $TargetObject = $null,

        [Parameter(ParameterSetName = 'Message')]
        [String]$Details,

        [Parameter(ParameterSetName = 'Message')]
        [Exception]$InnerException,

        [Parameter(ParameterSetName = 'ErrorRecord', Mandatory)]
        [ErrorRecord]$ErrorRecord,

        $Cmdlet = $PSCmdlet,

        [Switch]$Terminating
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'ErrorRecord') {
            $ErrorRecordObj = $ErrorRecord
        } else {
            $EffectiveException = if ($InnerException) {
                [System.Exception]::new($Message.Message, $InnerException)
            } else {
                $Message
            }
            $ErrorRecordObj = [ErrorRecord]::new(
                $EffectiveException,
                $ErrorId,
                $Category,
                $TargetObject
            )
            if ($Details) {
                $ErrorRecordObj.ErrorDetails = [ErrorDetails]::new($Details)
            }
        }
        if ($Terminating) {
            $Cmdlet.ThrowTerminatingError($ErrorRecordObj)
        } else {
            $Cmdlet.WriteError($ErrorRecordObj)
        }
    }
}
