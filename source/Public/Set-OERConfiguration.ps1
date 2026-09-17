function Set-OERConfiguration {
    <#
    .SYNOPSIS
    Updates an existing Tenant Profile configuration.

    .DESCRIPTION
    Updates the tenant id, sovereign cloud, naming templates, or default values of an existing Tenant
    Profile for a tenant alias. This command is update-only: it emits a non-terminating error if no
    profile exists for the alias and directs the caller to New-OERConfiguration. Only the supplied
    sections are replaced; sections that are not passed are preserved from the existing profile.
    Serialization is delegated to the private Export-OERConfiguration helper. The returned object
    carries the full profile shape, including the Naming, Defaults and Environment sections -- whether
    just updated or preserved from the existing profile -- not just the tenant alias, id, and path. At
    least one of -TenantId, -Naming, -Defaults or -Environment must be supplied or a non-terminating
    NothingToUpdate error is emitted. Supports -WhatIf and -Confirm.

    A profile file that cannot be parsed is left BYTE-UNCHANGED on disk and reported with a
    non-terminating TenantProfileMalformed error, rather than being rewritten from an empty read.
    The same error refuses any update whose resulting profile would carry no TenantId, because
    Connect-OER -TenantAlias accepts such a profile as a successful lookup and signs in against the
    operator's home tenant. A profile that has already lost its TenantId is still repairable here by
    supplying -TenantId.

    .PARAMETER TenantAlias
    The alias of the existing tenant profile to update. Accepts pipeline input by property name so
    that Get-OERConfiguration | Set-OERConfiguration works without specifying -TenantAlias explicitly.
    The alias becomes a file name on disk, so it is restricted to letters, digits, dot, underscore
    and hyphen; anything else is rejected with an InvalidTenantAlias error.

    .PARAMETER TenantId
    Optional new tenant GUID or domain. When omitted, the existing value is preserved. Accepts
    pipeline input by property name so a piped Get-OERConfiguration object flows its TenantId.

    .PARAMETER Naming
    Optional replacement naming-template hashtable. When omitted, the existing value is preserved.
    Accepts pipeline input by property name so a piped Get-OERConfiguration object flows its Naming.

    .PARAMETER Defaults
    Optional replacement defaults hashtable. When omitted, the existing value is preserved. Accepts
    pipeline input by property name so a piped Get-OERConfiguration object flows its Defaults.

    .PARAMETER BasePath
    The base directory for profile files. Defaults to the user's Omnicit.EntraRBAC config folder.

    .PARAMETER Environment
    Optional replacement sovereign cloud: 'Global', 'USGov', 'USGovDoD' or 'China'. When omitted, the
    existing stored value is preserved (or, if the profile never had one, it stays absent -- this
    parameter can only ever ADD or REPLACE a stored cloud, never invent a default in its absence).
    Unlike the four profile parameters above it, this one does NOT accept pipeline input by property
    name: a profile that stores no cloud would pipe an empty string at this parameter's ValidateSet,
    and the binder refuses the whole call. A piped Get-OERConfiguration object still keeps its cloud
    unchanged -- preserved from the file on disk by the same code that preserves it for an ordinary
    Set-OERConfiguration call, which needs no pipeline binding at all.

    .EXAMPLE
    Set-OERConfiguration -TenantAlias contoso -Defaults @{ ActivationMaxHours = 4 }
    Updates the contoso profile defaults while preserving its tenant id and naming templates.

    .EXAMPLE
    Set-OERConfiguration -TenantAlias contoso-gcc -Environment USGov
    Marks an existing contoso-gcc profile as a US Government (GCC High) tenant, leaving every other
    section of the profile untouched.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$TenantAlias,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$TenantId,
        [Parameter(ValueFromPipelineByPropertyName)]
        [hashtable]$Naming,
        [Parameter(ValueFromPipelineByPropertyName)]
        [hashtable]$Defaults,
        # USERPROFILE is a Windows-only variable and this module declares CompatiblePSEditions
        # Core, so binding this default threw on Linux and macOS before the body ever ran. .NET
        # returns the same directory as $env:USERPROFILE on Windows -- the resolved path is
        # unchanged there -- and the home directory on Linux and macOS.
        [string]$BasePath = (Join-Path $(
                $ProfileRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
                if ($ProfileRoot) { $ProfileRoot } else { $HOME }
            ) '.config/Omnicit.EntraRBAC/Profiles'),

        # Declared LAST on purpose, matching Connect-OER's own -Environment and New-OERConfiguration's
        # above. Positional binding follows DECLARATION order, so inserting this anywhere above would
        # silently change what an existing positional -Naming or -Defaults argument binds to. No
        # default value: an unsupplied -Environment must preserve whatever is already on disk (or its
        # absence), never overwrite it with 'Global'.
        #
        # And deliberately NOT ValueFromPipelineByPropertyName, unlike the four profile parameters
        # above it. A ValidateSet and property-name binding cannot coexist here:
        # ConvertTo-OERTenantConfiguration ALWAYS emits an Environment property, and an unbound
        # [string] parameter bound from it is '', not absent -- so every profile written without a
        # cloud piped '' straight at the ValidateSet and the binder refused the entire call with
        # ParameterArgumentValidationError,Set-OERConfiguration. That broke
        # Get-OERConfiguration | Set-OERConfiguration for 100% of profiles created before this key
        # existed, left the profile unmodified, and lost the update in silence under
        # -ErrorAction SilentlyContinue. Adding '' to the ValidateSet would be worse still: a round
        # trip would then silently DELETE a stored cloud. Nothing is lost by dropping the binding,
        # since the round trip preserves a stored cloud through $Existing.Environment below --
        # exactly as it preserves Naming and Defaults for a caller who names neither.
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment
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

        # Get-OERConfiguration | Set-OERConfiguration is unaffected by this guard: the piped object
        # binds TenantId (and Naming/Defaults when the profile has them) by property name, so the
        # round trip always has at least TenantId bound and never trips it -- Get-OERConfiguration
        # refuses to emit a profile with no TenantId at all, so that term is never empty. Environment
        # is deliberately NOT in that list and never binds from a piped object; see the reason on its
        # own declaration above. It reaches the write through the preserve path below instead, so a
        # stored cloud still survives the round trip.
        $UpdatableBound = @('TenantId', 'Naming', 'Defaults', 'Environment') | Where-Object { $PSBoundParameters.ContainsKey($_) }
        if (-not $UpdatableBound) {
            Write-CmdletError `
                -Message ([System.Exception]::new('No updatable property was supplied. Pass at least one of -TenantId, -Naming, -Defaults, or -Environment.')) `
                -ErrorId 'NothingToUpdate' `
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
                -Message ([System.Exception]::new("No Tenant Profile exists for alias '$TenantAlias' at '$Path'. Use New-OERConfiguration to create it.")) `
                -ErrorId 'ProfileNotFound' `
                -Category ObjectNotFound `
                -TargetObject $TenantAlias `
                -Cmdlet $PSCmdlet
            return
        }

        # Import-PowerShellDataFile fails NON-terminatingly on an unparsable file and returns $null.
        # Unguarded, that made $Existing null and the preserve-what-was-not-passed logic below wrote
        # the file straight back with an EMPTY TenantId -- destroying whatever good data was still
        # recoverable from the broken file and recreating exactly the empty-TenantId profile
        # Get-OERConfiguration now refuses. Refuse to touch a profile that cannot be read.
        $Existing = $null
        try {
            $Existing = Import-PowerShellDataFile -Path $Path -ErrorAction Stop
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new("Tenant Profile '$TenantAlias' at '$Path' could not be parsed and was NOT modified: $($PSItem.Exception.Message)")) `
                -ErrorId 'TenantProfileMalformed' `
                -Category InvalidData `
                -TargetObject $Path `
                -Cmdlet $PSCmdlet
            return
        }

        $Configuration = @{ TenantId = if ($PSBoundParameters.ContainsKey('TenantId')) { $TenantId } else { $Existing.TenantId } }
        $ResolvedNaming      = if ($PSBoundParameters.ContainsKey('Naming'))      { $Naming }      else { $Existing.Naming }
        $ResolvedDefaults    = if ($PSBoundParameters.ContainsKey('Defaults'))    { $Defaults }    else { $Existing.Defaults }
        $ResolvedEnvironment = if ($PSBoundParameters.ContainsKey('Environment')) { $Environment } else { $Existing.Environment }
        if ($null -ne $ResolvedNaming)      { $Configuration.Naming = $ResolvedNaming }
        if ($null -ne $ResolvedDefaults)    { $Configuration.Defaults = $ResolvedDefaults }
        if ($null -ne $ResolvedEnvironment) { $Configuration.Environment = $ResolvedEnvironment }

        # Same reasoning as the read guard in Get-OERConfiguration: never leave a profile on disk
        # without a TenantId, because Connect-OER -TenantAlias accepts that as a successful lookup
        # and signs in against the operator's home tenant. The check is on the RESOLVED value, not on
        # $Existing, so a profile that has already lost its TenantId is still repairable here by
        # passing -TenantId -- what is refused is a write that would leave the file without one.
        if (-not $Configuration.TenantId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Tenant Profile '$TenantAlias' at '$Path' declares no TenantId and was NOT modified. Supply -TenantId to repair it.")) `
                -ErrorId 'TenantProfileMalformed' `
                -Category InvalidData `
                -TargetObject $Path `
                -Cmdlet $PSCmdlet
            return
        }

        # A RESOLVED Environment outside the four supported sovereign clouds must never be written
        # back or returned. -Environment itself can never carry an invalid value (its own ValidateSet
        # already refuses that at parameter binding), so the only way $ResolvedEnvironment can be
        # invalid here is the PRESERVE path: $Existing.Environment came straight off disk with no
        # validation at all, unlike Get-OERConfiguration's read path, which is the one other place a
        # stored Environment is checked. Without this guard, a hand-edited or pre-validation profile's
        # bad value would round-trip silently through THIS cmdlet's own output object and back onto
        # disk unchanged and unreported -- the exact "invalid stored cloud" case, just reached through
        # the write path instead of the read path. Reuses Get-OERCloudEndpoint the same way
        # Get-OERConfiguration does, for the same reason: it is the single owner of the valid-cloud
        # list, so no unsupported value is silently treated as though none were stored.
        if ($ResolvedEnvironment) {
            try {
                $null = Get-OERCloudEndpoint -Environment $ResolvedEnvironment
            } catch {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Tenant Profile '$TenantAlias' at '$Path' carries an unsupported stored Environment value '$ResolvedEnvironment' and was NOT modified. Supply a valid -Environment (Global, USGov, USGovDoD or China) to repair it.")) `
                    -ErrorId 'TenantProfileMalformed' `
                    -Category InvalidData `
                    -TargetObject $Path `
                    -Cmdlet $PSCmdlet
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($Path, "Update Tenant Profile for alias '$TenantAlias'")) {
            Export-OERConfiguration -Configuration $Configuration -Path $Path
            ConvertTo-OERTenantConfiguration `
                -TenantAlias $TenantAlias `
                -TenantId $Configuration.TenantId `
                -Environment $ResolvedEnvironment `
                -Naming $ResolvedNaming `
                -Defaults $ResolvedDefaults `
                -Path $Path
        }
    }
}
