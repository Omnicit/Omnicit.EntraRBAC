function Get-OERConfiguration {
    <#
    .SYNOPSIS
    Reads one or all Tenant Profile configurations from disk.

    .DESCRIPTION
    Loads Tenant Profile PSD1 files and returns them as objects tagged Omnicit.EntraRBAC.TenantConfiguration.
    With -TenantAlias only the matching profile is returned; without it, every profile in the base
    directory is returned. Returns nothing when no profiles exist. This is a read-only command and
    does not modify any files. When enumerating every profile (no -TenantAlias), a profile file whose
    basename fails the same safe-file-name check as -TenantAlias (for example one written before that
    check existed, using a space or a non-ASCII letter) is still returned, but a warning names the file
    and explains it cannot be targeted by -TenantAlias until it is renamed on disk.

    A profile file that cannot be parsed, that parses but declares no TenantId, or that declares an
    Environment value outside the four supported sovereign clouds, is skipped with a non-terminating
    TenantProfileMalformed error naming the file, and enumeration continues with the remaining
    profiles. Such a file is never returned as a TenantConfiguration object with an empty TenantId,
    because Connect-OER -TenantAlias would accept that as a successful lookup and sign in against the
    operator's home tenant rather than the intended customer tenant. An unrecognized Environment value
    is likewise never let through as though the profile had named no cloud at all, because Connect-OER
    treats absence as an instruction to fall back to Global -- silently applying that same fallback to
    a value that WAS stored, just wrong, would sign in against the wrong cloud boundary.

    .PARAMETER TenantAlias
    Optional alias to return a single profile. When omitted, all profiles are returned. The alias
    becomes a file name on disk, so it is restricted to letters, digits, dot, underscore and
    hyphen; anything else is rejected with an InvalidTenantAlias error.

    .PARAMETER BasePath
    The base directory for profile files. Defaults to the user's Omnicit.EntraRBAC config folder.

    .EXAMPLE
    Get-OERConfiguration
    Returns all stored tenant profiles.

    .EXAMPLE
    Get-OERConfiguration -TenantAlias contoso
    Returns the tenant profile stored for the contoso alias.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
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
        if ($TenantAlias -and -not (Test-OERTenantAlias -Value $TenantAlias)) {
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

        if (-not (Test-Path $BasePath)) { return }

        if ($TenantAlias) {
            # Resolve-OERProfilePath throws ProfilePathEscapesBase only for a pathological -BasePath
            # (the alias itself was already validated above); a public cmdlet must never let that
            # terminate the pipeline, so it is converted to a non-terminating error here.
            try {
                $Single = Resolve-OERProfilePath -TenantAlias $TenantAlias -BasePath $BasePath
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
            $Files = if (Test-Path $Single) { Get-Item $Single } else { @() }
        } else {
            $Files = Get-ChildItem -Path $BasePath -Filter '*.psd1' -ErrorAction SilentlyContinue
        }

        foreach ($File in $Files) {
            # A profile written before Test-OERTenantAlias existed (or hand-copied onto disk) can have
            # a basename outside the safe-file-name character set -- a space or a non-ASCII letter, for
            # example. Such a file is unreadable, unwritable and undeletable through -TenantAlias (the
            # cmdlets validate the alias before it ever becomes a path), but it must still be LISTED
            # here so an operator running a bare Get-OERConfiguration can discover it exists at all.
            if (-not $TenantAlias -and -not (Test-OERTenantAlias -Value $File.BaseName)) {
                Write-Warning "Tenant Profile file '$($File.FullName)' has a basename that is not a valid -TenantAlias (only letters, digits, dot, underscore and hyphen are accepted). It cannot be read, updated or removed by alias until it is renamed on disk."
            }

            # Import-PowerShellDataFile fails NON-terminatingly on an unparsable file and returns
            # $null. Outside a guard that produced a normal-looking TenantConfiguration with an
            # EMPTY TenantId (-TenantId is not mandatory on ConvertTo-OERTenantConfiguration), which
            # Connect-OER accepts as a successful alias lookup -- Initialize-OERAuth then falls back
            # to 'organizations' and signs in against the OPERATOR'S HOME TENANT instead of the
            # customer tenant. -ErrorAction Stop routes the parse failure into the catch below.
            $Data = $null
            try {
                $Data = Import-PowerShellDataFile -Path $File.FullName -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $ParseErr = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Tenant Profile '$($File.BaseName)' at '$($File.FullName)' could not be parsed and was skipped: $($PSItem.Exception.Message)"),
                    'TenantProfileMalformed', [System.Management.Automation.ErrorCategory]::InvalidData, $File.FullName
                )
                $PSCmdlet.WriteError($ParseErr)
                continue
            }

            # A file can parse cleanly and still carry no TenantId -- an empty hashtable, or a
            # hand-edited profile that only sets Naming. TenantId is the one required key in the
            # profile schema, and an object emitted without it is the same wrong-tenant hazard as an
            # unparsable file, so it is refused here rather than handed to Connect-OER.
            if (-not $Data -or -not $Data.TenantId) {
                $EmptyErr = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Tenant Profile '$($File.BaseName)' at '$($File.FullName)' declares no TenantId and was skipped. Repair it with Set-OERConfiguration -TenantAlias '$($File.BaseName)' -TenantId <id>."),
                    'TenantProfileMalformed', [System.Management.Automation.ErrorCategory]::InvalidData, $File.FullName
                )
                $PSCmdlet.WriteError($EmptyErr)
                continue
            }

            # A stored Environment value outside the four supported sovereign clouds is a
            # hand-edited-file case, not a caller mistake -- New-/Set-OERConfiguration only ever write
            # one of the four values their own -Environment ValidateSet allows. Get-OERCloudEndpoint is
            # the single owner of the valid-cloud list (see its own .DESCRIPTION) and throws for
            # anything it does not recognize; that throw is caught here and reported the same way a
            # missing TenantId is reported above, instead of letting an unrecognized value reach
            # Connect-OER, where an ABSENT Environment falls back to Global -- silently applying that
            # same fallback to a value that WAS stored, just wrong, is exactly what this sprint forbids.
            if ($Data.Environment) {
                try {
                    $null = Get-OERCloudEndpoint -Environment $Data.Environment
                } catch {
                    $CloudErr = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Tenant Profile '$($File.BaseName)' at '$($File.FullName)' declares an unsupported Environment value '$($Data.Environment)' and was skipped. Valid values are Global, USGov, USGovDoD and China. Repair it with Set-OERConfiguration -TenantAlias '$($File.BaseName)' -Environment <value>."),
                        'TenantProfileMalformed', [System.Management.Automation.ErrorCategory]::InvalidData, $File.FullName
                    )
                    $PSCmdlet.WriteError($CloudErr)
                    continue
                }
            }

            # A hand-edited profile can have a Naming/Defaults section that is not a hashtable (an
            # array, a string, ...), which fails ConvertTo-OERTenantConfiguration's typed parameter
            # binding with a TERMINATING error. That is caught here so one malformed file produces a
            # non-terminating error for THIS file and the loop continues with the rest of the profiles,
            # instead of aborting the whole enumeration and silently hiding every profile after it.
            try {
                ConvertTo-OERTenantConfiguration `
                    -TenantAlias $File.BaseName `
                    -TenantId $Data.TenantId `
                    -Environment $Data.Environment `
                    -Naming $Data.Naming `
                    -Defaults $Data.Defaults `
                    -Path $File.FullName `
                    -ErrorAction Stop
            } catch {
                $Err = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Tenant Profile '$($File.BaseName)' at '$($File.FullName)' is malformed and was skipped: $($PSItem.Exception.Message)"),
                    'TenantProfileMalformed', [System.Management.Automation.ErrorCategory]::InvalidData, $File.FullName
                )
                $PSCmdlet.WriteError($Err)
                continue
            }
        }
    }
}
