function Remove-OERConfiguration {
    <#
    .SYNOPSIS
    Deletes a Tenant Profile configuration file.

    .DESCRIPTION
    Removes the Tenant Profile PSD1 file for a tenant alias from disk. Emits a non-terminating error
    when no profile exists for the alias. Because deleting configuration is a potentially disruptive
    operation it declares a Medium confirm impact and supports -WhatIf and -Confirm.

    .PARAMETER TenantAlias
    The alias of the tenant profile to delete. Accepts pipeline input by property name so that
    Get-OERConfiguration | Remove-OERConfiguration works without specifying -TenantAlias explicitly.
    The alias becomes a file name on disk, so it is restricted to letters, digits, dot, underscore
    and hyphen; anything else is rejected with an InvalidTenantAlias error.

    .PARAMETER BasePath
    The base directory for profile files. Defaults to the user's Omnicit.EntraRBAC config folder.

    .EXAMPLE
    Remove-OERConfiguration -TenantAlias contoso
    Deletes the contoso tenant profile after prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$TenantAlias,
        # USERPROFILE is a Windows-only variable and this module declares CompatiblePSEditions
        # Core, so binding this default threw on Linux and macOS before the body ever ran. .NET
        # returns the same directory as $env:USERPROFILE on Windows -- the resolved path is
        # unchanged there -- and the home directory on Linux and macOS.
        [string]$BasePath = (Join-Path $(
                $ProfileRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
                if ($ProfileRoot) { $ProfileRoot } else { $HOME }
            ) '.config/Omnicit.EntraRBAC/Profiles')
    )
    process {
        if (-not (Test-OERTenantAlias -Value $TenantAlias)) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Tenant alias '$TenantAlias' is not a valid profile name. Use only letters, digits, " +
                    "dot, underscore and hyphen (no path separators and no '..').")) `
                -ErrorId 'InvalidTenantAlias' `
                -Category InvalidArgument `
                -TargetObject $TenantAlias `
                -Cmdlet $PSCmdlet
            return
        }

        # Resolve-OERProfilePath throws ProfilePathEscapesBase only for a pathological -BasePath (the
        # alias itself was already validated above); a public cmdlet must never let that terminate the
        # pipeline, so it is converted to a non-terminating error here.
        try {
            $Path = Resolve-OERProfilePath -TenantAlias $TenantAlias -BasePath $BasePath
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message $PSItem.Exception `
                -ErrorId 'ProfilePathEscapesBase' `
                -Category SecurityError `
                -TargetObject $TenantAlias `
                -Cmdlet $PSCmdlet
            return
        }
        if (-not (Test-Path $Path)) {
            Write-CmdletError `
                -Message ([System.Exception]::new("No Tenant Profile exists for alias '$TenantAlias' at '$Path'.")) `
                -ErrorId 'ProfileNotFound' `
                -Category ObjectNotFound `
                -TargetObject $TenantAlias `
                -Cmdlet $PSCmdlet
            return
        }
        if ($PSCmdlet.ShouldProcess($Path, "Remove Tenant Profile for alias '$TenantAlias'")) {
            Remove-Item -Path $Path -Force
        }
    }
}
