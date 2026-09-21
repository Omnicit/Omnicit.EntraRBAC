# Omnicit.EntraRBAC

`Omnicit.EntraRBAC` is a PowerShell 7.2+ (Core-only) module for Omnicit AB and its customers for
managing RBAC building blocks across many Entra ID and Azure tenants. It covers Entra ID groups
and PIM, Administrative Units, Entitlement Management (Catalogs, Access Packages, Resources),
Access Reviews, Azure resources and RBAC, Azure PIM, plus a JSON inventory and a declarative apply
engine. It is built by Omnicit AB for its own and its customers' tenants, is MIT licensed, and is
destined for the public PowerShell Gallery once 1.0.0 is cut. Until then it is installed from a
build artifact or a build from source.

All 90 cmdlets carry the `OER` command prefix. Every cmdlet has full comment-based help, so
`Get-Help <cmdlet> -Full` and `Get-Help about_Omnicit.EntraRBAC` are authoritative for details this
README summarises. `Get-OERRequiredScope` is authoritative for permissions -- see
[Permissions](#permissions).

---

## Requirements

- **PowerShell 7.2 or later** (Core only; Windows PowerShell 5.x is not supported)
- **AzAuth** >= 2.9.0 (`Get-AzToken` -- token acquisition for all credential types)
- **Microsoft.Graph.Authentication** >= 2.36.0 (`Connect-MgGraph`)

No Az PowerShell module is required. Azure Resource Manager calls are made directly with a token
from AzAuth, so `-IncludeARM` needs nothing beyond the two modules above. An Az PowerShell session
you started yourself is left alone: this module never establishes an Az context, and
`Disconnect-OER` does not sign one out.

---

## Install / Import

### From the PowerShell Gallery (after 1.0.0 is published)

The module is destined for the public PowerShell Gallery. It is **not published yet** -- the build
deliberately defines no `publish` workflow until 1.0.0 is ready, so the command below will not
resolve a package before that release. Use one of the paths under it in the meantime.

```powershell
Install-PSResource -Name Omnicit.EntraRBAC              # PSResourceGet
Install-Module -Name Omnicit.EntraRBAC -Scope CurrentUser   # PowerShellGet 2.x
```

### From a build artifact (.nupkg)

The CI Build stage produces a versioned `.nupkg`. To install one that was handed to you, register
the folder holding it as a local repository and install from there. This is the supported
consumer path until the Gallery release.

```powershell
# 1. Register the folder that contains the .nupkg as a repository
Register-PSResourceRepository -Name OmnicitLocal -Uri '/path/to/the/downloaded/artifact' -Trusted

# 2. Install from it
Install-PSResource -Name Omnicit.EntraRBAC -Repository OmnicitLocal

Import-Module Omnicit.EntraRBAC
```

A `.nupkg` is also a zip file: renaming it to `.zip`, expanding it into a folder named
`Omnicit.EntraRBAC` on `$env:PSModulePath`, and deleting the NuGet metadata files works as a
manual fallback where registering a repository is not possible.

### For contributors -- build from source

```powershell
# 1. Bootstrap build dependencies (first time only)
./build.ps1 -ResolveDependency -Tasks noop

# If the bootstrap fails with "Requested value 'V2' was not found" (a PSResourceGet
# compatibility error), add -UseModuleFast:
./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast

# 2. Build the module
./build.ps1 -Tasks build

# 3. Import the built module (replace <ver> with the actual version, e.g. 1.0.0)
Import-Module ./output/module/Omnicit.EntraRBAC/<ver>/Omnicit.EntraRBAC.psd1
```

### For contributors -- import from source

```powershell
# Ensure AzAuth and Microsoft.Graph.Authentication are on $env:PSModulePath
# (tip: prepend output/RequiredModules after a bootstrap build)
$env:PSModulePath = (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath

Import-Module ./source/Omnicit.EntraRBAC.psd1 -Force
```

Run the authoritative test gate (Pester, PSScriptAnalyzer and the code-coverage threshold) with
`./build.ps1 -Tasks test`. Build before testing: coverage is measured against the built output.

---

## Quick Start

### Connect

```powershell
# Interactive browser sign-in (default)
Connect-OER -TenantId 'contoso.onmicrosoft.com'

# Device code (headless / SSH)
Connect-OER -TenantId 'contoso.onmicrosoft.com' -DeviceCode

# Client secret (SecureString -- never plain text)
$Secret = Read-Host 'Client secret' -AsSecureString
Connect-OER -TenantId 'contoso.onmicrosoft.com' -ClientId '<appId>' -ClientSecret $Secret

# Client certificate from a PFX file
Connect-OER -TenantId 'contoso.onmicrosoft.com' -ClientId '<appId>' -CertificatePath './certs/app.pfx'

# Client certificate (in-memory X509Certificate2 object, Windows only -- Cert: is a Windows-only PS drive)
$Cert = Get-Item Cert:\CurrentUser\My\<thumbprint>
Connect-OER -TenantId 'contoso.onmicrosoft.com' -ClientId '<appId>' -Certificate $Cert

# Client certificate (in-memory X509Certificate2 object, cross-platform)
# X509Certificate2 is a .NET API: it resolves a relative path against the process working
# directory, not PowerShell's $PWD. Resolve through PowerShell first so this still works after
# Set-Location changes $PWD away from the process working directory.
$Password = Read-Host 'PFX password' -AsSecureString
$Cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    (Resolve-Path './certs/app.pfx').Path, $Password)
Connect-OER -TenantId 'contoso.onmicrosoft.com' -ClientId '<appId>' -Certificate $Cert

# Managed identity (system-assigned)
Connect-OER -ManagedIdentity

# Managed identity (user-assigned)
Connect-OER -ManagedIdentity -ClientId '<managedIdentityClientId>'

# Also connect to Azure (required for every Azure/ARM cmdlet)
Connect-OER -TenantId 'contoso.onmicrosoft.com' -IncludeARM

# Connect using a stored Tenant Profile alias
Connect-OER -TenantAlias contoso
```

Calling `Connect-OER` explicitly is optional -- all OER cmdlets call `Initialize-OERAuth`
automatically on first use.

### Disconnect

```powershell
Disconnect-OER
```

Clears this module's cached tokens and session state and disconnects Microsoft Graph. An Az
PowerShell session you started yourself is left connected -- run `Disconnect-AzAccount` yourself if
you want to end that one too.

### Switching tenants

One PowerShell session works in one tenant at a time. Whether a later `Connect-OER` call naming a
different tenant actually switches depends on the sign-in type:

| Sign-in type | A later call naming another tenant |
|---|---|
| Client secret | Reuses the credential built for the earlier tenant, so the switching sign-in fails by default -- or, with `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH` set, silently reaches the earlier tenant instead -- until you run `Connect-OER ... -Force` |
| Device code | Does not send the tenant you name; its token may come from the signed-in account's own tenant when that account cannot obtain one in the tenant you name -- and the switching call may not return at all: see the known limitation below |
| Managed identity | Does not send the tenant you name; its token normally comes from the identity's own tenant |
| Interactive | Signs in to the tenant you name |
| Certificate | Signs in to the tenant you name |

**Known limitation -- a device code tenant switch can stop responding.** In a PowerShell process
where a device code sign-in has already completed, a further device code sign-in naming a different
tenant, with no `-Force`, never returns: no device code is printed, no error is raised, and the call
does not come back. Ctrl+C is the only escape, and it leaves the credential AzAuth keeps for the
process in an unknown state, so exit the PowerShell session afterwards rather than retrying in it.
Pass `Connect-OER ... -Force` on the switching call -- measured to cure it every time it was used --
or start a new PowerShell session, which begins from a fresh credential. Not every device code
tenant switch is affected: the first device code sign-in in a process is fine, and so is a switch
made straight after a sign-in with `-IncludeARM`, whose Azure Resource Manager token is acquired
under a different application and so leaves AzAuth holding a freshly built credential.

The module warns in two cases. It warns before a client secret sign-in for the same application
when the tenant you name differs from the one the credential AzAuth is currently holding for that
application was built for, and no Force is on the call: you did not pass `-Force`, and the module
did not add Force itself for a sovereign-cloud switch. AzAuth only rebuilds that credential for
`-Force`, for a different application, or for a different kind of sign-in -- a plain retry of the
same switch, with none of those, reuses the same credential and keeps warning every time, whether
the earlier attempt was silently answered from the old tenant or refused outright. This is the
module's own view: a `Get-AzToken` call made outside the module does not update it, and it resets
only when Omnicit.EntraRBAC itself is re-imported.

It also warns after a sign-in of any type that names a tenant by domain, when that tenant differs
from the one named by the last session this module established in the process and the token was
issued by the same tenant that issued that session's token. That comparison survives
`Disconnect-OER`, so disconnecting and reconnecting to another tenant is still checked, but it does
not fire for a sign-in that names no tenant, and it cannot check the very first sign-in in a process
or the first one after Omnicit.EntraRBAC is re-imported.

Neither warning stops the sign-in, but under `-WarningAction Stop` (or
`$WarningPreference = 'Stop'`) either one does -- the pre-call warning before any token is
requested, the post-call warning before the session is created -- the same safe direction as the
module's existing ambient `AZURE_AUTHORITY_HOST` warning.

`Disconnect-OER` clears only this module's own session state; it does not clear the credential
AzAuth keeps for the process, and the tenant-switch check above does not depend on that state -- it
keeps its own record, so disconnecting and reconnecting to another tenant is still checked.
`Connect-OER -Force` is the supported way, inside the same PowerShell process, to move a client
secret sign-in to a new tenant.

Name tenants by their tenant ID (a GUID) -- including a Tenant Profile's `TenantId` -- rather than
by domain: with a GUID the module refuses a token issued for another tenant outright, where a
domain-named request can only be warned about.

```powershell
# Move a client secret sign-in for the same application to another tenant
Connect-OER -TenantId '00000000-0000-0000-0000-000000000000' -ClientId $AppId -ClientSecret $Secret -Force
```

This same information is also available offline via `Get-Help about_Omnicit.EntraRBAC`
(SWITCHING TENANTS).

---

## Tenant Profiles

Tenant Profiles store per-tenant configuration (TenantId, naming templates, default values) in
PSD1 files under `<home>/.config/Omnicit.EntraRBAC/Profiles/<alias>.psd1`, where `<home>` is the
current user's profile folder as .NET reports it (falling back to `$HOME`) -- the same directory as
`$env:USERPROFILE` on Windows, and the user's home directory on Linux and macOS.

A profile may also carry an optional `Environment` key naming the sovereign cloud that tenant lives
in -- `Global`, `USGov`, `USGovDoD` or `China`. `Connect-OER -TenantAlias` reads it automatically, so
the cloud does not have to be repeated on every call; see [Sovereign Clouds](#sovereign-clouds). Only
`TenantId` is required; every other key is optional.

```powershell
# Create a new profile
New-OERConfiguration -TenantAlias contoso -TenantId '00000000-0000-0000-0000-000000000000'

# Create a profile for a tenant in a sovereign cloud
New-OERConfiguration -TenantAlias contoso-govhigh `
    -TenantId '22222222-2222-2222-2222-222222222222' -Environment USGov

# Create with naming templates and defaults
New-OERConfiguration -TenantAlias fabrikam `
    -TenantId '11111111-1111-1111-1111-111111111111' `
    -Naming @{ Group = 'role_sec_{area}_{tier}'; Catalog = 'CAT-{org}-{scope}' } `
    -Defaults @{ ActivationMaxHours = 8; Catalog = 'CAT-IT-PRG-Core' }

# Read profiles
Get-OERConfiguration                        # all profiles
Get-OERConfiguration -TenantAlias contoso   # one profile

# Update an existing profile (preserves sections not specified)
Set-OERConfiguration -TenantAlias contoso -Defaults @{ ActivationMaxHours = 4 }

# Remove a profile (prompts for confirmation)
Remove-OERConfiguration -TenantAlias contoso

# Connect using a stored profile
Connect-OER -TenantAlias contoso
```

---

## Sovereign Clouds

`Connect-OER -Environment` and `Initialize-OERAuth -Environment` select the sovereign cloud a
session signs in to and calls. Four values are supported:

| `-Environment` | Cloud | Graph endpoint | Azure Resource Manager endpoint |
|---|---|---|---|
| `Global` (default) | Worldwide commercial cloud | `graph.microsoft.com` | `management.azure.com` |
| `USGov` | GCC High | `graph.microsoft.us` | `management.usgovcloudapi.net` |
| `USGovDoD` | DoD | `dod-graph.microsoft.us` | `management.usgovcloudapi.net` |
| `China` | 21Vianet | `microsoftgraph.chinacloudapi.cn` | `management.chinacloudapi.cn` |

**Microsoft 365 GCC uses the commercial (`Global`) endpoints and needs no `-Environment` at all.**
Only GCC High, DoD and a 21Vianet tenant are separate cloud boundaries; GCC itself is not.

The chosen cloud becomes part of the session: every later cmdlet calls the cloud the session was
established in, and switching clouds re-authenticates instead of reusing a token minted at the
previous cloud's authority.

```powershell
# Sign in to a GCC High tenant and also acquire an Azure Resource Manager token
Connect-OER -TenantId 'contoso.onmicrosoft.us' -Environment USGov -IncludeARM
```

A Tenant Profile's optional `Environment` key (see [Tenant Profiles](#tenant-profiles)) stores the
cloud for that tenant, so `Connect-OER -TenantAlias` picks it up automatically without repeating
`-Environment` on every call; an explicit `-Environment` on the command line still overrides it.

```powershell
New-OERConfiguration -TenantAlias contoso-govhigh -TenantId '<guid>' -Environment USGov
Connect-OER -TenantAlias contoso-govhigh -IncludeARM   # signs in to USGov automatically
```

**Name the tenant explicitly and consistently.** The session is keyed on the tenant exactly as you
spell it, so a later call naming a tenant the session was not established for inherits nothing from
it -- including the same tenant written as a GUID one time and as a domain the next, and a
`Connect-OER -Environment USGov` with no `-TenantId` at all, which records the tenant as
`organizations` rather than as your tenant. The cloud then resets to `Global` and that call signs in
at the commercial authority. Its token and its endpoints stay consistent with each other, so nothing
crosses a cloud boundary, but the sign-in fails at the authority with an error that names the tenant
and never the cloud, which makes it easy to misread. Pass the same `-TenantId` spelling on every
call, or use a Tenant Profile whose `Environment` key carries the cloud for you.

**Known limitation:** PIM-for-Groups is pinned to the Microsoft Graph `beta` endpoint (see
[Permissions](#permissions) and `docs/development/rationale.md`), and beta endpoint availability in
US Government and China clouds is not established. A sovereign tenant that needs PIM-for-Groups may
find that pinned beta path behaves differently, or not at all, from the commercial cloud this module
is built and tested against.

---

## WhatIf and Confirm Support

All state-changing cmdlets support `-WhatIf` and `-Confirm`. Destructive operations on
high-value objects (e.g. removing groups, access packages) use `ConfirmImpact = High` and emit
a warning before proceeding.

```powershell
New-OERConfiguration -TenantAlias contoso -TenantId '<guid>' -WhatIf
Remove-OERConfiguration -TenantAlias contoso -Confirm
```

---

## Available Cmdlets

All 90 exported cmdlets, grouped by the area they manage. The groups below are for orientation
only -- **they are not permission boundaries**, so this section makes no claim about scopes. Ask
`Get-OERRequiredScope` instead; see [Permissions](#permissions).

### Authentication (2)

- `Connect-OER`, `Disconnect-OER`

### Tenant Profiles (4)

- `New-OERConfiguration`, `Get-OERConfiguration`, `Set-OERConfiguration`,
  `Remove-OERConfiguration`

### Groups and PIM for Groups (12)

- `New-OERGroup`, `Get-OERGroup`, `Set-OERGroup`, `Remove-OERGroup`
- `Add-OERGroupMember`, `Get-OERGroupMember`, `Remove-OERGroupMember`
- `Add-OERGroupEligibility`, `Get-OERGroupEligibility`, `Remove-OERGroupEligibility`
- `Get-OERGroupPimPolicy`, `Set-OERGroupPimPolicy`

### Administrative Units (9)

- `New-OERAdministrativeUnit`, `Get-OERAdministrativeUnit`, `Set-OERAdministrativeUnit`,
  `Remove-OERAdministrativeUnit`
- `Add-OERAdministrativeUnitMember`, `Remove-OERAdministrativeUnitMember`
- `Add-OERAdministrativeUnitScopedRole`, `Get-OERAdministrativeUnitScopedRole`,
  `Remove-OERAdministrativeUnitScopedRole`
- `New-OERGroup` accepts `-AdministrativeUnit` to place a new group into an AU at creation time.

### Entitlement Management (24)

Covers the full catalog -> resource -> access package -> policy -> assignment chain.

**Catalogs**

- `New-OERCatalog`, `Get-OERCatalog`, `Set-OERCatalog`, `Remove-OERCatalog`

**Catalog resources** -- add groups, applications, or SharePoint sites to a catalog so they can
be included in access packages:

- `Add-OERCatalogResource`, `Get-OERCatalogResource`, `Remove-OERCatalogResource`

**Access packages**

- `New-OERAccessPackage`, `Get-OERAccessPackage`, `Set-OERAccessPackage`,
  `Remove-OERAccessPackage`
- `Add-OERAccessPackageResourceRole`, `Get-OERAccessPackageResourceRole`,
  `Remove-OERAccessPackageResourceRole` -- bind, list or unbind a catalog resource role
  (e.g. group Member) on an access package

**Assignment policy builders** -- compose the nested settings, then pass them to a policy cmdlet:

- `New-OERAccessPackageApprovalStage` -- compose an approval stage (duration, approvers,
  justification requirement, escalation)
- `New-OERAccessPackageRequestorScope` -- compose the requestor scope (`AllMemberUsers`,
  `AllConfiguredConnectedOrganizationUsers`, `NoSubjects`, or a specific user/group list)
- `New-OERAccessPackageRequestorSettings` -- compose the granular requestor settings
  (self-request, manager request and manager level, custom schedule, self-extend)

**Assignment policies**

- `New-OERAccessPackageAssignmentPolicy`, `Get-OERAccessPackageAssignmentPolicy`,
  `Set-OERAccessPackageAssignmentPolicy`, `Remove-OERAccessPackageAssignmentPolicy`

**Assignments** -- admin-driven grant and revoke:

- `New-OERAccessPackageAssignment`, `Get-OERAccessPackageAssignment`,
  `Remove-OERAccessPackageAssignment`

> **SharePoint note:** to onboard SharePoint sites as catalog resources the service principal
> must also hold `Sites.FullControl.All` (application permission on SharePoint, not Graph).
> This permission is separate from the Graph `EntitlementManagement.ReadWrite.All` scope and
> must be granted manually in the tenant.

### Access Reviews (10)

Access review definitions and instances for access packages.

- `New-OERAccessReviewDefinition`, `Get-OERAccessReviewDefinition`,
  `Set-OERAccessReviewDefinition`, `Remove-OERAccessReviewDefinition`
- `New-OERAccessReviewStage` -- compose a multi-stage review stage before creating the definition
- `Get-OERAccessReviewInstance`, `Get-OERAccessReviewInstanceDecision`
- `Stop-OERAccessReviewInstance`, `Invoke-OERAccessReviewInstanceDecision`,
  `Send-OERAccessReviewReminder`

### Azure inventory and RBAC (7)

Requires an ARM token: connect with `Connect-OER -IncludeARM`, or let the cmdlet acquire one.

- `Get-OERManagementGroup`, `Get-OERSubscription`
- `Get-OERRoleDefinition` -- read built-in and custom role definitions
- `Get-OERRoleAssignment`, `New-OERRoleAssignment`, `Set-OERRoleAssignment`,
  `Remove-OERRoleAssignment` -- `Set-OERRoleAssignment` edits description, condition and
  conditionVersion in place

### Azure resource groups and resources (5)

- `New-OERResourceGroup`, `Get-OERResourceGroup`, `Set-OERResourceGroup`,
  `Remove-OERResourceGroup`
- `Get-OERResource` -- list resources in a subscription or resource group, optionally with their
  role-assignment delegations (`-IncludeRoleAssignments`, `-ResolveNames`)

### Azure PIM -- assignment lifecycle (8)

- `New-OEREligibleRoleAssignment`, `Get-OEREligibleRoleAssignment`,
  `Remove-OEREligibleRoleAssignment`
- `New-OERActiveRoleAssignment`, `Get-OERActiveRoleAssignment`,
  `Remove-OERActiveRoleAssignment`
- `Enable-OEREligibleRoleAssignment`, `Disable-OEREligibleRoleAssignment` -- activate and
  deactivate an existing eligibility

### Azure PIM -- policy engine (3)

- `Get-OERRoleManagementPolicy`, `Set-OERRoleManagementPolicy` -- read and update the activation,
  approval, MFA, notification and permanent-eligibility rules that govern a role at a scope
- `New-OERPolicyNotificationRule` -- compose a notification rule to pass to
  `Set-OERRoleManagementPolicy -NotificationRule`

### Inventory and JSON orchestration (4)

- `Get-OERInventory` -- read tenant state into the round-trippable inventory shape
- `Export-OERInventory` -- write that shape to a bundle folder (JSON, schema, LLM prompt, README)
- `Test-OERStructure` -- validate a structure document offline, with no tenant call
- `Invoke-OERStructure` -- apply a structure document idempotently in dependency order, with
  `-WhatIf` plan mode and opt-in child-scope `-Prune`

### Permissions (1)

- `Get-OERRequiredScope` -- report the Graph permissions and Azure roles one or more cmdlets need

### Conditional Access (1)

- `Get-OERAuthenticationContext` -- list the tenant's Conditional Access authentication contexts,
  optionally only the published ones (`-Available`) that a PIM policy can actually require

---

## Permissions

Ask the module, rather than reading a table that has to be kept in step by hand:

```powershell
# What does one cmdlet need?
Get-OERRequiredScope -Cmdlet New-OERGroup, Add-OERAdministrativeUnitScopedRole

# The consent list for a whole workflow, deduplicated
Get-OERRequiredScope -Cmdlet New-OERGroup, Add-OERGroupMember, Add-OERGroupEligibility -Unique

# Everything, to hand to whoever grants admin consent in a new tenant
Get-OERRequiredScope -Unique
```

It needs no tenant and no sign-in, so it answers before `Connect-OER` and against no tenant at all.

Three things worth knowing about the answers:

- **The area a cmdlet belongs to is not its permission boundary.** Microsoft Graph grants
  permissions by the resource a call touches, so a single scope line covering a whole functional
  area is wrong by construction. The three `*AdministrativeUnitScopedRole` cmdlets write directory
  role memberships, not unit memberships, and need `RoleManagement.ReadWrite.Directory`;
  `Get`/`Set-OERGroupPimPolicy` hit `roleManagementPolicies` and need
  `RoleManagementPolicy.*.AzureADGroup`, not the `PrivilegedEligibilitySchedule.*` permissions the
  eligibility cmdlets in the same area use.
- **Each answer is transitive.** It covers the cmdlet's own calls plus every call its internal
  helpers make, including the directory reads behind friendly-name parameters such as `-User`,
  `-Group` and `-ServicePrincipal`. Consenting to what is listed is enough for every parameter form;
  `Note` says so where a permission is needed for only one of them.
- **`Transport` disambiguates an empty list.** `Graph`, `Arm`, `GraphAndArm`, or `None` for the
  cmdlets that touch no tenant at all -- Tenant Profile file operations, the in-memory builders, and
  `Test-OERStructure`. An empty `GraphScope` on an ARM-only cmdlet means "none needed", never
  "unknown".

Where an entry lists `User.ReadBasic.All`, `Group.Read.All` and `Application.Read.All`, a single
`Directory.Read.All` covers all three; the narrower ones are listed because the module prefers least
privilege. Where an entry lists `Directory.Read.All` instead, that cmdlet reads
`directoryObjects`, which accepts nothing narrower -- so the covered permissions are deliberately
*not* also listed, and `Note` says which parameter makes the call. Azure cmdlets additionally need
an ARM token -- connect with `Connect-OER -IncludeARM`, or let the cmdlet acquire one.

The values are taken from Microsoft Learn's published permission tables, and
`tests/QA/requiredscope.tests.ps1` gates the table against the module's own call graph, so a cmdlet
that starts calling a new endpoint fails the build until its entry is updated. What no static check
can prove is that Microsoft's documented permission is the one the service actually enforces; that
is confirmed by granting consent in a test tenant.

---

## Walkthroughs

### Entitlement Management, end to end

```powershell
# 1. Create a catalog
$Cat = New-OERCatalog -DisplayName 'CAT-IT-Core' -Description 'Core IT access'

# 2. Resolve the group to publish, then add it to the catalog as a resource
$SalesGroupId = (Get-OERGroup -Group 'sec_sales').Id
Add-OERCatalogResource -Catalog $Cat.DisplayName -GroupId $SalesGroupId

# 3. Create an access package inside the catalog
New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core'

# 4. Bind the group Member role to the access package
Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'CAT-IT-Core' `
    -ResourceOriginId $SalesGroupId -Role 'Member'

# 5. Compose an assignment policy
$Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
$Stage = New-OERAccessPackageApprovalStage -DurationDays 7 `
    -Manager -RequireJustification
$Pol = New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' `
    -DisplayName 'Default' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30

# 6. Grant access to a user. This returns an assignment REQUEST, not the assignment itself.
New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy $Pol.Id -User 'alice@contoso.com'

# 7. Once the request is delivered, list the package's assignments and revoke one by its own id
Get-OERAccessPackageAssignment -AccessPackage 'AP-Sales' | Format-Table Id, TargetDisplayName, State
Remove-OERAccessPackageAssignment -AssignmentId '<id from the list above>'
```

### Inventory to apply document, end to end

Read the tenant, hand the bundle to an LLM (or edit the JSON by hand), validate offline, preview,
then apply. `Test-OERStructure` never touches the tenant, and `Invoke-OERStructure -WhatIf` only
reads.

```powershell
# 1. Export the current posture into a timestamped bundle (JSON + schema + LLM prompt + README)
$Bundle = Export-OERInventory -OutputPath ./exports `
    -Include Groups, AdministrativeUnits, Catalogs, AccessPackages, RoleAssignments

# 2. Edit the inventory.json in that bundle, or feed the bundle to an LLM and take its proposal.
#    Then validate the result offline -- no tenant call, no authentication.
Test-OERStructure -Path ./exports/<bundle>/inventory.json

# 3. Preview every change the apply engine would make
Invoke-OERStructure -Path ./exports/<bundle>/inventory.json -WhatIf

# 4. Apply it. Add -Prune to also remove undeclared child objects (members, role assignments)
#    inside the scopes the document declares; top-level objects are never deleted.
Invoke-OERStructure -Path ./exports/<bundle>/inventory.json

# A read-only round trip needs no file at all
Get-OERInventory -Include Groups, Catalogs | Test-OERStructure
```

---

## Documentation

Everything below lives in this repository. It is not installed with the module, so clone the
repository (or browse it on GitHub) to read it.

- [docs/inventory-to-llm/README.md](docs/inventory-to-llm/README.md) -- the export -> LLM ->
  validate -> apply loop in full, including the `schema.json` / `Test-Json` escape hatch.
- [docs/examples/example-structure.json](docs/examples/example-structure.json) -- a worked apply
  document showing every section the engine understands.
- `Get-Help about_Omnicit.EntraRBAC` -- the in-box overview: command cohorts, Azure scope forms,
  the Tenant Profile schema, access package policy settings and the duration vocabulary. This one
  ships inside the module.
- [CHANGELOG.md](CHANGELOG.md) -- what changed in each version.
- [docs/development/rationale.md](docs/development/rationale.md) -- for contributors: the history
  behind the house rules in `CLAUDE.md`, from the bearer-token scrub to the ARM transport design.

---

## A note on issue and pull request numbers

Source comments, tests and documents throughout this repository cite issue and pull request numbers
such as `#71` or `see #64`. **These refer to the module's development history before 1.0.0, which
took place in a private repository, and cannot be looked up here.** They are kept deliberately:
they are the anchors the rationale and the house rules are written against, and rewriting roughly
580 references across the tree immediately before a release would have been a large, risky change
for no reader benefit. Read them as provenance markers, not as links.

The reasoning they point at is not lost. Where a rule exists because something failed, the
explanation lives in [docs/development/rationale.md](docs/development/rationale.md), and
[CHANGELOG.md](CHANGELOG.md) records what each version delivered. Issue numbers opened from 1.0.0
onwards refer to this repository and resolve normally.

---

## License

MIT -- see [LICENSE](LICENSE). (c) 2026 Omnicit AB.
