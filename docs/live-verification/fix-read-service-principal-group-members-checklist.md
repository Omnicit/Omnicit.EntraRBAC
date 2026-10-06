# Live verification checklist -- service principals are among a group's members and owners (fix/read-service-principal-group-members)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s91-`.** The
prerequisite script creates two plain security groups, `oer-s91-grp` and `oer-s91-nested`, makes
`oer-s91-nested` a member of `oer-s91-grp`, and makes the service principal `oer-live-cc-noperm` a
member AND an owner of `oer-s91-grp`. The service principal itself is never changed: only those two
links inside a prefixed group are created, and they go when the group is deleted. It is a different
service principal from the one signed in, so what this file measures is not an artefact of a
principal reading itself. No directory role is assigned and no policy is changed.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS91Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). The 403 checks sign in as
`oer-live-cc-noperm`, the same certificate's identity with no permission at all; a 403 there is the
expected answer, not a stop. Every sign-in is app-only; nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown both
run first with `-WhatIf`; read the plan against the `Expect:` line before running the line that
writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s91/` -- the
library writes its transcript, the baseline and the export bundles there, and the folder is
git-ignored. Every block below prints through the library's redactor, so its lines are already
redacted per [README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the
same id the same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. The library keeps one
real-to-placeholder map per step, outside the clone and the operator's notes, and deletes it after
the write-up. **No credential, token, application id or certificate thumbprint is ever printed.**
**Never render an error record** (`Format-List` on `$Error[0]` or on an `-ErrorVariable`): a raw
failure's record can carry the bearer token. Every block prints the error id and message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

**The defect (BL-13).** Microsoft Graph's `v1.0` `groups/{id}/members` does not list a service
principal that is a member, and `groups/{id}/owners` does not list a service principal that is an
owner -- both are documented on Microsoft Learn ("Known issues in Microsoft Graph": GET
/groups/{id}/members doesn't return service principals in v1.0; and the note on List group owners),
and the members half was measured with this identity on 2026-09-29
(`feat-directory-role-assignments-checklist.md`). `Get-OERGroup -IncludeMembers -IncludeOwners` and
`Get-OERGroupMember` read exactly those two collections, so the module never saw such a member or
owner. The export, which reads through `Get-OERGroup`, therefore wrote a group's members and owners
without its service principals, and a later `Invoke-OERStructure -Prune` run by any identity whose
read DOES list them would remove every such membership and ownership as undeclared. The read
succeeded, so the guard for unread collections never fired.

Section 1 of this file measures the reads BEFORE the fix, on the unchanged build, and decides which
object types the fix has to read typed (the step's scope, point 3). Sections 2 to 5, written once the
fix is built, verify it against the same objects.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS91Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same five lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and its no-permission
  twin `oer-live-cc-noperm`. `oer-live-cc` creates and deletes two groups and adds two members and one
  owner to one of them with the permissions it already holds; this file adds none.
- The **built module** in the step's own worktree, built there with `./build.ps1 -Tasks build`, and
  the environment variable `OER_LIVE_REPO` naming that worktree. Each block's fifth line sets the
  session's `Repo` to it, so the module loads from the worktree's build; the main clone is never
  checked out on another commit or branch (S.1 reads that it was not). Section 1 runs on the build of
  the UNCHANGED branch (`main` at the step's start); sections 2 to 5 on the build of the fix.

### S.1. The module loads from the build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-OerLiveStep "The worktree's build: version $(Split-Path -Leaf $Psd1.DirectoryName), built $($Psd1.LastWriteTimeUtc.ToString("yyyy-MM-dd HH:mm 'UTC'", [cultureinfo]::InvariantCulture))"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded); the worktree on `fix/read-service-principal-group-members` with 0 tracked
changes; the build's version and time.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone, and the run would load whatever the main clone last built.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is the worktree's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True` (app-only certificate session with the identity's app id,
the app name `oer-live-cc`, the test tenant, the service principal of that app id named
`oer-live-cc` and the token's signed-in object; the organization name, a verified domain and the
organization id; the ARM token from the certificate; the test subscription belongs to the test
tenant and is Enabled), `identity check passed: True`, and `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result:

### 0.2. Identity check as oer-live-cc-noperm, the module session

- [ ] **0.2** The no-permission identity signs in to a module session.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** the lines for `oer-live-cc-noperm`: app-only with its app id `True`, the app name in the
session is `oer-live-cc-noperm`: `True`, the test tenant `True`, the ARM token from the certificate
`True`, `identity check passed: True`, and `The module is the worktree's build: True`.
**Failure looks like:** any `False` -- STOP; sections 1 and 5 need this session.

Result:

### 0.3. The prerequisite script's plan

- [ ] **0.3** `-WhatIf` plans only `oer-s91-` targets in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s91\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s91-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s91-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; `The service principal of the noperm app id is named
oer-live-cc-noperm: True`; the sweep reads all six collections and finds no `oer-s91-` object; the
plan names the transcript and the baseline under `raw\s91\` and, in the tenant, the groups
`oer-s91-grp` and `oer-s91-nested` and the three links `oer-s91-grp: member oer-s91-nested`,
`oer-s91-grp: member oer-live-cc-noperm (service principal)` and `oer-s91-grp: owner
oer-live-cc-noperm (service principal)` -- five tenant targets, every one starting with `oer-s91-`;
`WhatIf: nothing was created, removed or written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result:

### 0.4. The prerequisite script, for real

- [ ] **0.4** The test objects exist: the two groups, the group and the service principal as members, the service principal as owner.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written and read back before the first write; `Created group
oer-s91-grp` and `Created group oer-s91-nested`; each of the three links added and then listed from
the OTHER side (the nested group's and the service principal's `memberOf`, the service principal's
`ownedObjects`), so the read this file measures is not the read that confirms the setup; the summary
with both groups `present`; exit code `0`. A `likely replication delay` line on a fresh object is
expected, and is not a failure.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.4 again (the script
completes an earlier run) or tear down; never sign in another way.

Result:

### 1. The reads before the fix, measured on the unchanged build

Every request in this section goes through the module's OWN Graph transport, `Invoke-OERGraphRequest`
with `-All`, in the module's scope -- the exact path `Get-OERGroup` and `Get-OERGroupMember` take --
so a difference between two reads is Graph's, not a second client's. Each read prints its count and,
per object, its `@odata.type` and redacted id; a typed read also says, per object, whether the
untyped read listed it. The table these lines fill is the step's measurement, and point 3 of the
step's scope (which object types the fix reads typed) is decided from it.

### 1.1. Members: the untyped read against each typed read

- [ ] **1.1** The untyped `members` read, the typed reads for service principal, user, group, device and organizational contact, and the `beta` untyped read for the record.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
function Read-S91 {
    param([string]$Uri, [switch]$One)
    try {
        $R = & (Get-Module Omnicit.EntraRBAC) { param($U, $O) if ($O) { Invoke-OERGraphRequest -Uri $U -ErrorAction Stop } else { Invoke-OERGraphRequest -Uri $U -All -ErrorAction Stop } } $Uri $One.IsPresent
        $Rows = @(if ($One) { $R } else { @($R.value) | Where-Object { $null -ne $_ } })
        [PSCustomObject]@{ Ok = $true; Rows = $Rows; Error = '' }
    } catch {
        $E = "$($PSItem.FullyQualifiedErrorId) -- $($PSItem.Exception.Message)"
        $global:Error.Clear()
        [PSCustomObject]@{ Ok = $false; Rows = @(); Error = $E }
    }
}
$Gid = [string](Read-S91 -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).Rows[0].id
$Nid = [string](Read-S91 -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-nested'"))).Rows[0].id
$Sid = [string](Read-S91 -One -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.NoPermAppId)).Rows[0].id
Write-OerLiveStep "oer-s91-grp is $Gid; oer-s91-nested is $Nid; the service principal oer-live-cc-noperm is $Sid"
if (-not $Gid -or -not $Sid -or -not $Nid) { Write-OerLiveStep 'STOP: an id lookup returned nothing, so nothing below would measure anything.'; Disconnect-OerLive; return }
$Untyped = Read-S91 -Uri "v1.0/groups/$Gid/members"
$UntypedIds = @($Untyped.Rows | ForEach-Object { [string]$_.id })
Write-OerLiveStep "READ v1.0 members (untyped): ok $($Untyped.Ok); count $($Untyped.Rows.Count)$(if (-not $Untyped.Ok) { "; $($Untyped.Error)" })"
foreach ($Row in $Untyped.Rows) { Write-OerLiveStep "  untyped: $($Row.'@odata.type') $($Row.id)" }
foreach ($T in 'servicePrincipal', 'user', 'group', 'device', 'orgContact') {
    $R = Read-S91 -Uri "v1.0/groups/$Gid/members/microsoft.graph.$T"
    Write-OerLiveStep "READ v1.0 members/microsoft.graph.$($T): ok $($R.Ok); count $($R.Rows.Count)$(if (-not $R.Ok) { "; $($R.Error)" })"
    foreach ($Row in $R.Rows) { Write-OerLiveStep "  typed $($T): '$($Row.'@odata.type')' $($Row.id); in the untyped read: $($UntypedIds -contains [string]$Row.id)" }
}
$Beta = Read-S91 -Uri "beta/groups/$Gid/members"
Write-OerLiveStep "READ beta members (untyped, for the record): ok $($Beta.Ok); count $($Beta.Rows.Count)$(if (-not $Beta.Ok) { "; $($Beta.Error)" })"
foreach ($Row in $Beta.Rows) { Write-OerLiveStep "  beta: $($Row.'@odata.type') $($Row.id)" }
Disconnect-OerLive
```

**Expect (the record, predicted from the 2026-09-29 measurement and Microsoft Learn's known
issue):** the untyped `v1.0` read lists `oer-s91-nested` only (`#microsoft.graph.group`, count 1); the
typed service principal read lists `oer-live-cc-noperm` (count 1), with `in the untyped read: False`;
the typed group read lists `oer-s91-nested`, `in the untyped read: True`; the user, device and
organizational contact reads list nothing; the `beta` untyped read lists both. Whatever comes back is
the measurement: write it down as it is.
**Failure looks like:** a read that is not `ok` with a 401/403 -- STOP (a missing permission on the
app path, G6/G11); a typed read refused as unsupported (400) is a measurement, not a stop.

Result:

### 1.2. Owners: the untyped read against the typed service principal read

- [ ] **1.2** The untyped `owners` read and the typed service principal and user `owners` reads.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
function Read-S91 {
    param([string]$Uri, [switch]$One)
    try {
        $R = & (Get-Module Omnicit.EntraRBAC) { param($U, $O) if ($O) { Invoke-OERGraphRequest -Uri $U -ErrorAction Stop } else { Invoke-OERGraphRequest -Uri $U -All -ErrorAction Stop } } $Uri $One.IsPresent
        $Rows = @(if ($One) { $R } else { @($R.value) | Where-Object { $null -ne $_ } })
        [PSCustomObject]@{ Ok = $true; Rows = $Rows; Error = '' }
    } catch {
        $E = "$($PSItem.FullyQualifiedErrorId) -- $($PSItem.Exception.Message)"
        $global:Error.Clear()
        [PSCustomObject]@{ Ok = $false; Rows = @(); Error = $E }
    }
}
$Gid = [string](Read-S91 -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).Rows[0].id
$Sid = [string](Read-S91 -One -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.NoPermAppId)).Rows[0].id
Write-OerLiveStep "oer-s91-grp is $Gid; the service principal oer-live-cc-noperm is $Sid"
if (-not $Gid -or -not $Sid) { Write-OerLiveStep 'STOP: an id lookup returned nothing, so nothing below would measure anything.'; Disconnect-OerLive; return }
$Untyped = Read-S91 -Uri "v1.0/groups/$Gid/owners"
$UntypedIds = @($Untyped.Rows | ForEach-Object { [string]$_.id })
Write-OerLiveStep "READ v1.0 owners (untyped): ok $($Untyped.Ok); count $($Untyped.Rows.Count)$(if (-not $Untyped.Ok) { "; $($Untyped.Error)" })"
foreach ($Row in $Untyped.Rows) { Write-OerLiveStep "  untyped: $($Row.'@odata.type') $($Row.id)" }
foreach ($T in 'servicePrincipal', 'user') {
    $R = Read-S91 -Uri "v1.0/groups/$Gid/owners/microsoft.graph.$T"
    Write-OerLiveStep "READ v1.0 owners/microsoft.graph.$($T): ok $($R.Ok); count $($R.Rows.Count)$(if (-not $R.Ok) { "; $($R.Error)" })"
    foreach ($Row in $R.Rows) { Write-OerLiveStep "  typed $($T): '$($Row.'@odata.type')' $($Row.id); in the untyped read: $($UntypedIds -contains [string]$Row.id)" }
}
$Beta = Read-S91 -Uri "beta/groups/$Gid/owners"
Write-OerLiveStep "READ beta owners (untyped, for the record): ok $($Beta.Ok); count $($Beta.Rows.Count)$(if (-not $Beta.Ok) { "; $($Beta.Error)" })"
foreach ($Row in $Beta.Rows) { Write-OerLiveStep "  beta: $($Row.'@odata.type') $($Row.id)" }
Disconnect-OerLive
```

**Expect (the record):** the owners half has never been measured here. Microsoft Learn's note on
List group owners says service principals are not listed as group owners in `v1.0`; if that holds,
the untyped read lists nothing, and the typed service principal read lists `oer-live-cc-noperm` with
`in the untyped read: False`. The user read lists nothing (the prerequisite script adds no user owner,
and an app-only create adds no owner of its own). Whatever comes back is the measurement.
**Failure looks like:** a 401/403 -- STOP.

Result:

### 1.3. The service principal's own side

- [ ] **1.3** `servicePrincipals/{id}/memberOf` and `ownedObjects` for `oer-live-cc-noperm` name `oer-s91-grp`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
function Read-S91 {
    param([string]$Uri, [switch]$One)
    try {
        $R = & (Get-Module Omnicit.EntraRBAC) { param($U, $O) if ($O) { Invoke-OERGraphRequest -Uri $U -ErrorAction Stop } else { Invoke-OERGraphRequest -Uri $U -All -ErrorAction Stop } } $Uri $One.IsPresent
        $Rows = @(if ($One) { $R } else { @($R.value) | Where-Object { $null -ne $_ } })
        [PSCustomObject]@{ Ok = $true; Rows = $Rows; Error = '' }
    } catch {
        $E = "$($PSItem.FullyQualifiedErrorId) -- $($PSItem.Exception.Message)"
        $global:Error.Clear()
        [PSCustomObject]@{ Ok = $false; Rows = @(); Error = $E }
    }
}
$Gid = [string](Read-S91 -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).Rows[0].id
$Sid = [string](Read-S91 -One -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.NoPermAppId)).Rows[0].id
Write-OerLiveStep "oer-s91-grp is $Gid; the service principal oer-live-cc-noperm is $Sid"
if (-not $Gid -or -not $Sid) { Write-OerLiveStep 'STOP: an id lookup returned nothing, so nothing below would measure anything.'; Disconnect-OerLive; return }
foreach ($Rel in 'memberOf', 'ownedObjects') {
    $R = Read-S91 -Uri "v1.0/servicePrincipals/$Sid/$Rel"
    Write-OerLiveStep "READ v1.0 servicePrincipals/{id}/$($Rel): ok $($R.Ok); count $($R.Rows.Count); names oer-s91-grp: $(@($R.Rows | ForEach-Object { [string]$_.id }) -contains $Gid)$(if (-not $R.Ok) { "; $($R.Error)" })"
}
Disconnect-OerLive
```

**Expect:** both reads `ok`; `memberOf` names `oer-s91-grp: True`, and `ownedObjects` names
`oer-s91-grp: True` -- the links the untyped group reads in 1.1 and 1.2 may leave out exist.
**Failure looks like:** `False` on either -- the link does not exist, so 1.1 and 1.2 measure nothing;
run 0.4 again.

Result:

### 1.4. The module's own reads before the fix

- [ ] **1.4** `Get-OERGroupMember`, `Get-OERGroupMember -Owners`, `Get-OERGroup -IncludeMembers -IncludeOwners` and the export, on the unchanged build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "The service principal oer-live-cc-noperm is $Sid"
$Show = { param($Label, $Rows) Write-OerLiveStep "$($Label): count $(@($Rows).Count); the service principal listed: $(@(@($Rows) | ForEach-Object { [string]$_.PrincipalId }) -contains $Sid)"; foreach ($M in @($Rows)) { Write-OerLiveStep "  $($M.MemberType) '$($M.DisplayName)' ObjectType '$($M.ObjectType)' $($M.PrincipalId)" } }
$Members = @(Get-OERGroupMember -Group 'oer-s91-grp' -ErrorAction SilentlyContinue -ErrorVariable E1)
& $Show 'Get-OERGroupMember' $Members
$Owners = @(Get-OERGroupMember -Group 'oer-s91-grp' -Owners -ErrorAction SilentlyContinue -ErrorVariable E2)
& $Show 'Get-OERGroupMember -Owners' $Owners
$G = Get-OERGroup -Group 'oer-s91-grp' -IncludeMembers -IncludeOwners -ErrorAction SilentlyContinue -ErrorVariable E3
Write-OerLiveStep "Get-OERGroup: Members present $($null -ne $G.PSObject.Properties['Members']); Owners present $($null -ne $G.PSObject.Properties['Owners'])"
& $Show 'Get-OERGroup Members' $G.Members
& $Show 'Get-OERGroup Owners' $G.Owners
$Inv = Get-OERInventory -Include Groups -GroupFilter "startswith(displayName,'oer-s91-')" -ErrorAction SilentlyContinue -ErrorVariable E4 -WarningAction SilentlyContinue
$Entry = @($Inv.groups) | Where-Object { $_.displayName -eq 'oer-s91-grp' }
Write-OerLiveStep "Export oer-s91-grp: members [$(@($Entry.members) -join '; ')]; owners present $($null -ne $Entry.PSObject.Properties['owners']) [$(@($Entry.owners) -join '; ')]; the service principal in members: $(@($Entry.members) -contains $Sid); in owners: $(@($Entry.owners) -contains $Sid)"
foreach ($E in @(@($E1) + @($E2) + @($E3) + @($E4) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect (the defect, before the fix):** `Get-OERGroupMember` lists `oer-s91-nested` only, `the
service principal listed: False`; `-Owners` lists what 1.2's untyped read listed (nothing, if
Microsoft Learn's note holds); `Get-OERGroup` carries both properties with the same content; the
export writes `oer-s91-grp` with `members` holding `oer-s91-nested` and not the service principal,
and no `owners` key if the owner read is empty. No error.
**Failure looks like:** the service principal listed here -- then the unchanged build already sees
it, and the defect does not reproduce on this tenant; write that down as it is.

Result:

### 1.5. What the no-permission identity can read of the group

- [ ] **1.5** As `oer-live-cc-noperm`: the group itself, its members (untyped and typed) and its owners -- the input for section 5.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Gid = [string](@((& (Get-Module Omnicit.EntraRBAC) { param($U) Invoke-OERGraphRequest -Uri $U } ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).value)[0].id)
Write-OerLiveStep "oer-s91-grp is $Gid (read as oer-live-cc)"
Connect-OerLive -Arm -NoPerm
foreach ($U in "v1.0/groups/$Gid", "v1.0/groups/$Gid/members", "v1.0/groups/$Gid/members/microsoft.graph.servicePrincipal", "v1.0/groups/$Gid/owners", "v1.0/groups/$Gid/owners/microsoft.graph.servicePrincipal") {
    try {
        $R = & (Get-Module Omnicit.EntraRBAC) { param($X) Invoke-OERGraphRequest -Uri $X -ErrorAction Stop } $U
        Write-OerLiveStep "READ as noperm $($U -replace $Gid, '{id}'): ok; count $(if ($R.PSObject.Properties['value'] -or ($R -is [System.Collections.IDictionary] -and $R.Contains('value'))) { @($R.value).Count } else { 'one object' })"
    } catch {
        Write-OerLiveStep "READ as noperm $($U -replace $Gid, '{id}'): refused -- $($PSItem.FullyQualifiedErrorId) -- $($PSItem.Exception.Message)"
        $global:Error.Clear()
    }
}
Disconnect-OerLive
```

**Expect:** every read refused with `Authorization_RequestDenied` (403), the group read included --
the identity holds no permission, and owning `oer-s91-grp` gives an app-only token no read of it. If
so, `Get-OERGroup -IncludeMembers` as this identity stops at the group read, and section 5 cannot
reach `GroupMemberReadFailed` without answering the group read from a recording (decided there).
**Failure looks like:** a read that succeeds -- write it down: section 5 is then designed on it.

Result:

### 2. The module's reads after the fix

Sections 2 to 5 run on the build of the fix, built in the step's worktree with `./build.ps1 -Tasks
build` from the branch head named in 2.0.

### 2.0. The module loads from the fix's build in the step's own worktree

- [ ] **2.0** The worktree's build carries the fix, and the main clone is still on `main`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath); main clone on: $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Fix = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Get-OERGroupRelation' -Quiet)
$Typed = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'microsoft.graph.{2}' -Quiet)
Write-OerLiveStep "The worktree's build ($(Split-Path -Leaf $Psm1.DirectoryName), built $($Psm1.LastWriteTimeUtc.ToString("yyyy-MM-dd HH:mm 'UTC'", [cultureinfo]::InvariantCulture))) carries the single reader: $Fix; the typed read: $Typed"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`, the main clone on
`main`; the worktree at the branch head with 0 tracked changes; `carries the single reader: True;
the typed read: True`, and a build time after the head commit.
**Failure looks like:** any `False` -- build the worktree first, never while the gate runs.

Result:

### 2.1. Get-OERGroupMember: the service principal is a member and an owner

- [ ] **2.1** `Get-OERGroupMember -Group oer-s91-grp` lists the service principal with `ObjectType` `servicePrincipal`, and so does `-Owners`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "The service principal oer-live-cc-noperm is $Sid"
$Show = { param($Label, $Rows) Write-OerLiveStep "$($Label): count $(@($Rows).Count); the service principal listed: $(@(@($Rows) | Where-Object { [string]$_.PrincipalId -eq $Sid }).Count) time(s)"; foreach ($M in @($Rows)) { Write-OerLiveStep "  $($M.MemberType) '$($M.DisplayName)' ObjectType '$($M.ObjectType)' $($M.PrincipalId)" } }
$Members = @(Get-OERGroupMember -Group 'oer-s91-grp' -ErrorAction SilentlyContinue -ErrorVariable E1)
& $Show 'Get-OERGroupMember' $Members
$Owners = @(Get-OERGroupMember -Group 'oer-s91-grp' -Owners -ErrorAction SilentlyContinue -ErrorVariable E2)
& $Show 'Get-OERGroupMember -Owners' $Owners
foreach ($E in @(@($E1) + @($E2) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** `Get-OERGroupMember: count 2; the service principal listed: 1 time(s)`, `oer-s91-nested`
with `ObjectType 'group'` and `oer-live-cc-noperm` with `ObjectType 'servicePrincipal'`;
`Get-OERGroupMember -Owners: count 1; the service principal listed: 1 time(s)`, `Owner` with
`ObjectType 'servicePrincipal'`. No error. Before the fix (1.4) the counts were 1 and 0.
**Failure looks like:** the service principal missing, listed twice, or with an empty `ObjectType`.

Result:

### 2.2. Get-OERGroup -IncludeMembers -IncludeOwners

- [ ] **2.2** `Get-OERGroup` carries the service principal in `Members` and in `Owners`, with `ObjectType` `servicePrincipal`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "The service principal oer-live-cc-noperm is $Sid"
$G = Get-OERGroup -Group 'oer-s91-grp' -IncludeMembers -IncludeOwners -ErrorAction SilentlyContinue -ErrorVariable E3
Write-OerLiveStep "Get-OERGroup: Members present $($null -ne $G.PSObject.Properties['Members']); Owners present $($null -ne $G.PSObject.Properties['Owners'])"
foreach ($P in 'Members', 'Owners') {
    $Rows = @($G.$P)
    Write-OerLiveStep "Get-OERGroup $($P): count $($Rows.Count); the service principal listed: $(@($Rows | Where-Object { [string]$_.PrincipalId -eq $Sid }).Count) time(s)"
    foreach ($M in $Rows) { Write-OerLiveStep "  $($M.MemberType) '$($M.DisplayName)' ObjectType '$($M.ObjectType)' $($M.PrincipalId)" }
}
foreach ($E in @(@($E3) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** both properties present; `Members: count 2`, the service principal listed `1 time(s)`
with `ObjectType 'servicePrincipal'`; `Owners: count 1`, the same. No error.
**Failure looks like:** as in 2.1.

Result:

### 3. The export

### 3.1. Get-OERInventory: the service principal's id in members and owners

- [ ] **3.1** The export of the `oer-s91-` groups writes the service principal's id in `oer-s91-grp`'s `members` and `owners`, and reports nothing unread.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "The service principal oer-live-cc-noperm is $Sid"
$Inv = Get-OERInventory -Include Groups -GroupFilter "startswith(displayName,'oer-s91-')" -ErrorAction SilentlyContinue -ErrorVariable E4 -WarningAction SilentlyContinue
$Entry = @($Inv.groups) | Where-Object { $_.displayName -eq 'oer-s91-grp' }
Write-OerLiveStep "Export oer-s91-grp: members [$(@($Entry.members) -join '; ')]; owners present $($null -ne $Entry.PSObject.Properties['owners']) [$(@($Entry.owners) -join '; ')]"
Write-OerLiveStep "The service principal in members: $(@(@($Entry.members) | Where-Object { $_ -eq $Sid }).Count) time(s); in owners: $(@(@($Entry.owners) | Where-Object { $_ -eq $Sid }).Count) time(s)"
$Partial = @(@($E4) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
Write-OerLiveStep "InventoryPartial records: $($Partial.Count)"
foreach ($E in @(@($E4) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Doc = $Inv | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$Doc.groups = @($Doc.groups | Where-Object { $_.displayName -eq 'oer-s91-grp' })
$null = New-Item -ItemType Directory -Force -Path $Raw
$DocPath = Join-Path $Raw 'doc-s91-grp.json'
[System.IO.File]::WriteAllText($DocPath, ($Doc | ConvertTo-Json -Depth 50), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "The apply document for 3.2 and 4 (oer-s91-grp only, cut from this export, version $($Doc.version)) is raw\s91\doc-s91-grp.json"
Disconnect-OerLive
```

**Expect:** `members` holds the ids of `oer-s91-nested` and the service principal; `owners` is
present and holds the service principal's id; the service principal `1 time(s)` in each;
`InventoryPartial records: 0`; no error. Before the fix (1.4) the export had no service principal and
no `owners` key at all.
**Failure looks like:** the service principal missing, or an `InventoryPartial` naming
`groups/oer-s91-grp/members` or `/owners` -- a read the fix made unread.

Result:

### 3.2. The export's entry applied with -Prune -WhatIf, twice: only Unchanged

- [ ] **3.2** `Invoke-OERStructure -Prune -WhatIf` of `oer-s91-grp`'s exported entry plans no change and no removal, two runs in a row (G8), behind a read-only fence.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S91Seen = [System.Collections.Generic.List[string]]::new()
    $script:S91Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S91Transport) { $script:S91Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S91Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S91Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S91 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S91Transport @PSBoundParameters
    }
}
$DocPath = Join-Path $Raw 'doc-s91-grp.json'
foreach ($Run in 1, 2) {
    $Rows = @(Invoke-OERStructure -Path $DocPath -Include Groups -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
    $ByAction = ($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
    Write-OerLiveStep "Run $($Run): rows $($Rows.Count) [$ByAction]; warnings $(@($ApplyWarn).Count); errors $(@($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
    foreach ($R in $Rows) { Write-OerLiveStep "  $($R.Action) $($R.Item): $($R.Detail)" }
    foreach ($W in @($ApplyWarn)) { Write-OerLiveStep "  Warning: $W" }
}
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S91Seen.Count; NotGet = @($script:S91Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S91Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** each run: only `Unchanged` rows (among them `member '...' already present` for both
members and `owner '...' already present` for the service principal), no `Extra`, no `Skipped`
`would remove`, no `Failed`, no prune warning; the fence refused `0`. Before the fix a declared
service principal could never be `already present`: the engine did not see it.
**Failure looks like:** a planned removal or an `Updated` row -- the export and the engine disagree
about the group; `refused` above 0.

Result:

### 4. Apply with -Prune for real, oer-s91- only

### 4.1. The document declaring both members and the owner: Unchanged and 0 Removed, twice

- [ ] **4.1** `Invoke-OERStructure -Prune` for real (no `-WhatIf`) on the `oer-s91-grp` document gives only `Unchanged` and removes nothing, two runs in a row (G8).

The read-only fence stays in front of the module's Graph transport for this real run as well: the
run makes no `-WhatIf` plan, so every gate is passed for real, but a write -- which a correct run
does not attempt -- is refused and shows as `Failed` instead of reaching the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S91Seen = [System.Collections.Generic.List[string]]::new()
    $script:S91Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S91Transport) { $script:S91Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S91Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S91Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S91 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S91Transport @PSBoundParameters
    }
}
$DocPath = Join-Path $Raw 'doc-s91-grp.json'
$Doc = Get-Content -LiteralPath $DocPath -Raw | ConvertFrom-Json
Write-OerLiveStep "The document: groups $(@($Doc.groups).Count) ($(@($Doc.groups.displayName) -join ', ')); members [$(@($Doc.groups[0].members) -join '; ')]; owners [$(@($Doc.groups[0].owners) -join '; ')]"
foreach ($Run in 1, 2) {
    $Rows = @(Invoke-OERStructure -Path $DocPath -Include Groups -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
    $ByAction = ($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
    Write-OerLiveStep "Run $($Run) (real, -Prune): rows $($Rows.Count) [$ByAction]; Removed $(@($Rows | Where-Object Action -eq 'Removed').Count); warnings $(@($ApplyWarn).Count); errors $(@($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
    foreach ($R in $Rows) { Write-OerLiveStep "  $($R.Action) $($R.Item): $($R.Detail)" }
}
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S91Seen.Count; NotGet = @($script:S91Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S91Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** the document holds one group, `oer-s91-grp`, with both members and the service
principal as owner; each run: only `Unchanged` rows, `Removed 0`, no warning, no error; the fence
refused `0`.
**Failure looks like:** a `Removed`, `Updated` or `Failed` row, or `refused` above 0 -- STOP and read
it; never run 4.1 without the fence.

Result:

### 4.2. The same document without the service principal, -Prune -WhatIf: the removal is planned

- [ ] **4.2** With the service principal taken out of `members` and `owners`, `-Prune -WhatIf` plans its removal as a member, and the last-owner guard keeps it as the owner. No write.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S91Seen = [System.Collections.Generic.List[string]]::new()
    $script:S91Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S91Transport) { $script:S91Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S91Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S91Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S91 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S91Transport @PSBoundParameters
    }
}
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-s91-grp.json') -Raw | ConvertFrom-Json
$Doc.groups[0].members = @(@($Doc.groups[0].members) | Where-Object { $_ -ne $Sid })
$Doc.groups[0].owners = @(@($Doc.groups[0].owners) | Where-Object { $_ -ne $Sid })
$DocPath = Join-Path $Raw 'doc-s91-grp-without-sp.json'
[System.IO.File]::WriteAllText($DocPath, ($Doc | ConvertTo-Json -Depth 50), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "The document without $($Sid): members [$(@($Doc.groups[0].members) -join '; ')]; owners [$(@($Doc.groups[0].owners) -join '; ')]"
$Rows = @(Invoke-OERStructure -Path $DocPath -Include Groups -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
$ByAction = ($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
Write-OerLiveStep "Plan: rows $($Rows.Count) [$ByAction]; warnings $(@($ApplyWarn).Count); errors $(@($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
foreach ($R in $Rows) { Write-OerLiveStep "  $($R.Action) $($R.Item): $($R.Detail)" }
foreach ($W in @($ApplyWarn)) { Write-OerLiveStep "  Warning: $W" }
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S91Seen.Count; NotGet = @($script:S91Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S91Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** `members` without the service principal and `owners` empty; the plan: `Unchanged` for
`oer-s91-nested`; a `Skipped` row `would remove undeclared member '...'` naming the service
principal, with the warning `would remove undeclared member`; for the owner, an empty declared
`owners` reconciles the live owner set, and the only live owner is the service principal, so the
last-owner guard answers with a `Skipped` row `did not remove owner '...': it is the last remaining
owner`; no `Removed`, no `Failed`; the fence refused `0`. The engine now sees the service principal:
that is the step's point, and the plan for an undeclared member is the right outcome.
**Failure looks like:** no planned removal of the service principal -- the engine still does not
see it; a `Removed` row -- `-WhatIf` did not hold (the fence would refuse it).

Result:

### 5. The 403 checks, as oer-live-cc-noperm

1.5 measured that this identity reads `oer-s91-grp` itself, while the untyped member read and both
owner reads are refused (403). The two cmdlets therefore reach their member and owner reads live,
with no recording.

### 5.1. Get-OERGroupMember: the error and nothing else

- [ ] **5.1** As `oer-live-cc-noperm`, `Get-OERGroupMember -Group` (by id) and `-Owners` each write the refusal as itself and return nothing.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Gid = [string](@((& (Get-Module Omnicit.EntraRBAC) { param($U) Invoke-OERGraphRequest -Uri $U } ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).value)[0].id)
Write-OerLiveStep "oer-s91-grp is $Gid (read as oer-live-cc)"
if (-not $Gid) { Write-OerLiveStep 'STOP: the id lookup returned nothing.'; Disconnect-OerLive; return }
Connect-OerLive -Arm -NoPerm
foreach ($Owners in $false, $true) {
    $Label = if ($Owners) { 'Get-OERGroupMember -Owners' } else { 'Get-OERGroupMember' }
    $Out = @(Get-OERGroupMember -Group $Gid -Owners:$Owners -ErrorAction SilentlyContinue -ErrorVariable E5)
    $Recs = @(@($E5) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    Write-OerLiveStep "$($Label): output $($Out.Count); error records $($Recs.Count)"
    foreach ($E in $Recs) { Write-OerLiveStep "  Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
}
Disconnect-OerLive
```

**Expect:** for both: `output 0`, and an error record whose id starts with
`Authorization_RequestDenied` (the refusal as itself, never `GroupNotFound`); nothing else written.
**Failure looks like:** any output -- a partial list from a collection that was not read whole.

Result:

### 5.2. Get-OERGroup -IncludeMembers -IncludeOwners: no Members, no Owners, both errors

- [ ] **5.2** As `oer-live-cc-noperm`, `Get-OERGroup` returns the group without `Members` and `Owners`, and writes `GroupMemberReadFailed` and `GroupOwnerReadFailed`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Gid = [string](@((& (Get-Module Omnicit.EntraRBAC) { param($U) Invoke-OERGraphRequest -Uri $U } ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).value)[0].id)
Write-OerLiveStep "oer-s91-grp is $Gid (read as oer-live-cc)"
if (-not $Gid) { Write-OerLiveStep 'STOP: the id lookup returned nothing.'; Disconnect-OerLive; return }
Connect-OerLive -Arm -NoPerm
$G = Get-OERGroup -Group $Gid -IncludeMembers -IncludeOwners -ErrorAction SilentlyContinue -ErrorVariable E6
Write-OerLiveStep "Get-OERGroup: object $($null -ne $G) (id $($G.Id)); Members present $($null -ne $G.PSObject.Properties['Members']); Owners present $($null -ne $G.PSObject.Properties['Owners'])"
$Recs = @(@($E6) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
foreach ($Id in 'GroupMemberReadFailed', 'GroupOwnerReadFailed') { Write-OerLiveStep "$($Id): $(@($Recs | Where-Object { $_.FullyQualifiedErrorId -like "$Id*" }).Count)" }
foreach ($E in $Recs) { Write-OerLiveStep "  Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** the group object (its id), `Members present False`, `Owners present False`;
`GroupMemberReadFailed: 1` and `GroupOwnerReadFailed: 1`, each message naming the refusal
(`Authorization_RequestDenied`) and saying the property is omitted rather than reported as empty.
**Failure looks like:** a `Members` or `Owners` property (an unread collection presented as a fact),
or no group object at all -- then the group read itself was refused, unlike 1.5.

Result:

## Teardown

### T.1. The teardown's plan

- [ ] **T.1** `-Teardown -WhatIf` plans only the two `oer-s91-` groups.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s91\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s91-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s91-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the sweep finds `oer-s91-grp` and `oer-s91-nested` and nothing else; the teardown's six
steps, with only step 5 planning anything: `Delete the group` for the two groups (they are not
role-assignable, so step 4 removes no member); two tenant targets, both with the prefix; nothing
removed; exit code `0`.
**Failure looks like:** a target without the prefix -- STOP.

Result:

### T.2. The teardown

- [ ] **T.2** Both groups deleted; the service principal is back at its baseline (a member of no `oer-s91-` group, owner of nothing it did not own before).

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** `Deleted: group oer-s91-grp (204)` and `Deleted: group oer-s91-nested (204)`; `removed 2,
residue 0`; the sweep afterwards may still list a group deleted seconds ago (replication), and T.3
reads it again; `groups now 97, at the baseline 97; equal: True` (or the count of the moment, if
another run changed the tenant's groups -- then say so); `oer-live-cc-noperm memberOf: now 0, at the
baseline 0; the same objects: True` and the same for `ownedObjects`; exit code `0`.
**Failure looks like:** a residue line or exit code `3` -- the row stays in `raw\residue.json` and the
next prereq run retries it; a `False` on the service principal's lines after T.3's read-back -- STOP
(G11.5).

Result:

### T.3. Read back, and clean up

- [ ] **T.3** Minutes later: no `oer-s91-` object left, the baseline holds, no residue row, the main clone still on `main`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Exit code: $Code; the main clone is on: $MainBranch"
```

**Expect:** `no user, group, administrative unit, catalog, access package or app registration
starting with 'oer-s91-' is left`; the counts and both service principal lines `True`; `residue rows:
0`; exit code `0`; the main clone on `main`. Then, outside this file: the step's `raw\s91\` folder is
deleted once the results are copied in, and the redaction map with `Clear-OerLiveRedactionMap`.
**Failure looks like:** a prefixed object still listed after minutes, or a `False` -- STOP (G11.5).

Result:
