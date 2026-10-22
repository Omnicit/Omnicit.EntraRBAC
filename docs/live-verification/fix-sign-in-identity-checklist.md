# Live verification checklist -- the identity in the sign-in (fix/sign-in-identity)

**This branch does not merge until every box in sections S, 0, 1, 2, 3 and T has a written result.** A box with no
result line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible to run,
write "cannot be verified, and therefore we do not know" on its result line and say why; do not leave it blank and
do not tick it. A check that could not run for a stated reason is marked `[~]`, never `[x]`. **Section B lists what
is proved offline only (class B), and section C the one manual check (class C), the operator's optional check.**

**What this file writes to the tenant: nothing.** No check creates, changes or deletes a tenant object, so there is
no prerequisite script and no tenant teardown. `Invoke-OERStructure` runs only with `-WhatIf` against a minimal
document whose one group carries the step's prefix (`oer-s1113b-`), and a request fence refuses and counts every
write the module would send. What the checks write is local: the child processes' scripts, output files and logs
under the step's raw folder (`raw\s1113b\`). T.1 deletes it.

**The tenant's object names are never printed.** The blocks print counts, True/False, error ids and the step's own
prefixed names only.

**Who runs it.** The dedicated certificate identities `oer-live-cc` and `oer-live-cc-noperm`, through the OerLive
library, which lives beside the operator's copy of this file outside the repository (the repository's
`docs/live-verification/README.md`, first paragraph). Every sign-in is app-only, with the certificate; nothing here
signs in as a person. `oer-live-cc-noperm` is the second identity of the same tenant, used as "another identity"
and never for a write. A 401 or 403 is a stop.

**Permissions.** The reads use the permissions the two identities already hold. Granting a permission is the
operator's decision, never this checklist's.

**Sign-ins.** A block signs in through `Connect-OerLive -Arm`, which runs `Disconnect-OER` and `Disconnect-MgGraph`
first and then checks the identity as True/False, or through `Connect-OER` with the certificate. Every child process
installs the fence (H.1) right after its first sign-in: a token request without the certificate is refused, so
nothing prompts, and every Microsoft Graph and Azure Resource Manager request is counted and every write refused.

**Redact before you commit.** Every block prints through the library's redactor. **No credential, token, application
id, tenant id, subscription id, account, object id or certificate thumbprint is ever printed.** Each block runs in its
own child process whose WHOLE output (every stream) goes to a log in the raw folder, read only through OerLive's
redactor, and deleted by T.1.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main` before it
merges.

- **A. A nested sign-in** ("fix: refuse a sign-in nested under a superseded command before any token request",
  BL-91 b): `Initialize-OERAuth` asks `Get-OERSignInSupersession -OutsideCaller` directly after its BL-74 check, so a
  sign-in made while an outer command's sign-in has been replaced is refused with `SignInSuperseded` before any
  token request.
- **B. `-TenantId` binds the tenant, not the identity** ("fix: -TenantId binds the tenant, not the identity ...",
  BL-90): `Invoke-OERStructure` and the three builders compare the session with the one they began with also when
  `-TenantId` is bound, whenever that sign-in would take the session's identity for that tenant
  (`Test-OERSessionUsable`), and refuse with `SignInSuperseded`.
- **C. A renewal never continues as another account** ("fix: a renewal never continues as another account ...",
  BL-119): the sign-in identity carries the account (`SignInAccountId`) as a fifth term; a renewal whose Graph token
  names another object id than the session's is refused with `SignInSuperseded` and the session becomes that account
  (its cached ARM token dropped); a renewal's ARM token of another account is refused and not cached.

A live tenant is needed for what the unit tests cannot show: that the real `Connect-OER`, the real AzAuth tokens and
the real call stack of a pipeline give the refusals and, above all, that an ordinary run in one session is NOT
refused: a sign-in and a read, a renewal as the same identity, `-IncludeARM` after a Microsoft Graph sign-in,
`Connect-OER` switching identity, and `Invoke-OERStructure -TenantId -WhatIf`.

## What this file does not check, and why

- **The account picker's second account (BL-119, class C, C.1).** A renewal answered by another PERSON needs an
  interactive sign-in, which these identities never make. Section 3 drives the same decision with the real token of
  `oer-live-cc` against a session whose object id is moved in module scope; the unit tests prove the rest (B.1).
- **The outer frames refused after an account change, a token without an object id, and the order of the refusals
  (class B, B.1-B.3)**: each is a decision on values the unit tests set exactly.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads beside it.
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identities** `oer-live-cc` and `oer-live-cc-noperm`, enabled for the run.
- The **built module of this branch** in the step's own worktree, built there with `./build.ps1 -Tasks build`, and
  the environment variable `OER_LIVE_REPO` naming that worktree.

**Run H.1 first in the operator's process; every numbered block then runs its body in a child process through
`Invoke-S1113bBlock`.**

### H.1. Shared helpers

Loads OerLive and the configuration, and defines the child-process runner and the prologue every child runs: the
fence, the error-id counter and the module-scope readers. Nothing here signs in or writes to the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1113b-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = [System.IO.Path]::GetFullPath($env:OER_LIVE_REPO).TrimEnd('\', '/') }
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$null = New-Item -ItemType Directory -Path $Raw -Force
$Prefix = 'oer-s1113b-'
$NewIds = 'Test-OERSessionUsable', 'SignInAccountId', 'SignInAccountChanged', 'OutsideCaller'
$Prologue = @'
param($VaultDir, $Repo, $Out)
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1113b-' -ConfigDirectory $VaultDir
$Cfg.Repo = $Repo
$R = [ordered]@{}
$T = $Cfg.TenantId
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint) -ErrorAction Stop
$Doc = '{"version":"1.0","groups":[{"displayName":"oer-s1113b-plan","description":"A plan-only group of step 13b; -WhatIf creates nothing.","members":null,"owners":null}]}'
function Start-S1113bFence {
    # A token request without the certificate would prompt: refuse it. Count every token request and every
    # Graph and ARM request; refuse and count every write.
    $global:Tokens = 0; $global:Graph = 0; $global:Arm = 0; $global:Writes = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:Tokens++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S1113b fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"))
    $Fence = 'if ($PSBoundParameters.ContainsKey(''Method'') -and ([string]$Method).ToUpperInvariant() -ne ''GET'') { $global:Writes++; throw ''S1113b fence: a write request was refused.'' }'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:Graph++; $Fence; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:Arm++; $Fence; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"))
}
function Get-S1113bIds {
    # "id xN" for each distinct first id segment of a set of records.
    param($Records)
    $Ids = foreach ($X in @($Records)) {
        $Rec = if ($X -is [System.Management.Automation.ErrorRecord]) { $X } elseif ($X -is [System.Management.Automation.IContainsErrorRecord]) { $X.ErrorRecord } else { $null }
        if ($Rec) { ([string]$Rec.FullyQualifiedErrorId -split ',')[0] }
    }
    (@($Ids) | Group-Object | Sort-Object Name | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }) -join ', '
}
function Get-S1113bSuperseded {
    # The SignInSuperseded records of a set: the command each names, and whether its text is the account one.
    param($Records)
    @(foreach ($X in @($Records)) {
        $Rec = if ($X -is [System.Management.Automation.ErrorRecord]) { $X } elseif ($X -is [System.Management.Automation.IContainsErrorRecord]) { $X.ErrorRecord } else { $null }
        if ($Rec -and ([string]$Rec.FullyQualifiedErrorId).StartsWith('SignInSuperseded,')) {
            '{0}{1}{2}' -f [string]$Rec.TargetObject,
                $(if ($Rec.Exception.Message -match 'returned a token for another account') { ' (account text)' } else { '' }),
                $(if ($Rec.Exception.Message -match 'did not apply this document') { ' (document text)' } else { '' })
        }
    }) -join '; '
}
function Get-S1113bState { & (Get-Module -Name Omnicit.EntraRBAC) { $script:_OERAuthState } }
function Get-S1113bIdentity { & (Get-Module -Name Omnicit.EntraRBAC) { Get-OERSignInIdentity } }
function Get-S1113bTerm { param([int]$Index) [string]@(([string](Get-S1113bIdentity)) -split "`n")[$Index] }
function Invoke-S1113bRenewal {
    # A renewal of the session as Initialize-OERAuth's own callers make it (method and client named, as the
    # transports' refreshes do), with the certificate, from module scope.
    param($ClientId, [switch]$IncludeARM)
    & (Get-Module -Name Omnicit.EntraRBAC) { param($T, $A, $C, $Arm) Initialize-OERAuth -TenantId $T -AuthMethod ClientCertificate -ClientId $A -Certificate $C -IncludeARM:$Arm } $T $ClientId $Cert ([bool]$IncludeARM)
}
'@
$Epilogue = @'
$R | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Out -Encoding utf8NoBOM
'END'
'@
function Invoke-S1113bBlock {
    # Runs one block's body in a child pwsh, its whole output (every stream) into a log in the raw folder.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Body)
    $Child = Join-Path $Raw "block-$Name.ps1"
    $Out = Join-Path $Raw "result-$Name.json"
    $Log = Join-Path $Raw "block-$Name.log"
    Remove-Item -LiteralPath $Out -ErrorAction SilentlyContinue
    ($Prologue + "`n" + $Body + "`n" + $Epilogue) | Set-Content -LiteralPath $Child -Encoding utf8NoBOM
    & pwsh -NoProfile -File $Child -VaultDir $VaultDir -Repo $Cfg.Repo -Out $Out *> $Log
    Write-OerLiveStep "Child process $Name ended with END: $([bool](Select-String -LiteralPath $Log -SimpleMatch 'END' -Quiet))"
    if (Test-Path -LiteralPath $Out) { Get-Content -LiteralPath $Out -Raw | ConvertFrom-Json } else { $null }
}
function Show-S1113bLog {
    # Only for a failed block: its log, redacted.
    param([Parameter(Mandatory)][string]$Name)
    Get-Content -LiteralPath (Join-Path $Raw "block-$Name.log") | ForEach-Object { ConvertTo-OerLiveRedacted -Text $_ }
}
function Write-S1113bResult {
    # Prints every field of a block's result, through the redactor.
    param($Result)
    if ($null -eq $Result) { Write-OerLiveStep 'No result file: the block did not finish (read Show-S1113bLog).'; return }
    foreach ($P in $Result.PSObject.Properties) { Write-OerLiveStep "$($P.Name): $($P.Value)" }
}
```

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Found = @(foreach ($Id in $NewIds) { '{0}: {1}' -f $Id, [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch $Id -Quiet) })
Write-OerLiveStep "The branch build ($((Split-Path -Leaf (Split-Path -Parent $Psm1.FullName)))): $($Found -join '; ')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on `main`; the
worktree on this branch with 0 tracked changes; `True` on every mark.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone; a `False`
mark -- build the worktree first.

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113b] The module loads from a worktree that is not the main clone: True
[oer-s1113b] Main clone: branch main
[oer-s1113b] Worktree: branch fix/sign-in-identity; HEAD 16f4ceb docs: add the live checklist for the identity in the sign-in, and name the snapshot test right; tracked changes: 0
[oer-s1113b] The branch build (1.3.1): Test-OERSessionUsable: True; SignInAccountId: True; SignInAccountChanged: True; OutsideCaller: True
```

## 0. An ordinary run in one session is not refused

### 0.1. A sign-in and two reads; the identity carries the account

- [x] **0.1** After `Connect-OerLive -Arm` as oer-live-cc, the identity has five terms, its account term is the session's signed-in object, the account-change flag is off, and `Get-OERSubscription` and `Get-OERGroup` read with no error and no further token request. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '0-1' -Body @'
Connect-OerLive -Arm
Start-S1113bFence
$S = Get-S1113bState
$R.IdentityTerms = @(([string](Get-S1113bIdentity)) -split "`n").Count
$R.AccountTermIsSignedInObject = [bool]$S.SignedInObjectId -and ((Get-S1113bTerm 4) -ceq [string]$S.SignedInObjectId)
$R.AccountChangedFlag = [bool]$S.SignInAccountChanged
$Error.Clear()
$Subs = @(Get-OERSubscription -ErrorAction SilentlyContinue)
$Groups = @(Get-OERGroup -Filter 'securityEnabled eq true' -ErrorAction SilentlyContinue)
$R.SubscriptionsRead = $Subs.Count -gt 0
$R.GroupsRead = $Groups.Count
$R.Errors = "[$(Get-S1113bIds $Error)]"
$R.Requests = "Graph $global:Graph, ARM $global:Arm, writes $global:Writes, token requests $global:Tokens"
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; `IdentityTerms: 5`; `AccountTermIsSignedInObject: True`; `AccountChangedFlag: False`;
`SubscriptionsRead: True`; a group count; `Errors: []`; at least one Graph and one ARM request, 0 writes, 0 token
requests.
**Failure looks like:** four terms (the old build), an error id, or a token request (the session was not cached).

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed. The sign-in lines are from the child process log, through the redactor.
[oer-s1113b] Omnicit.EntraRBAC 1.3.1 loaded from REPO\.claude\worktrees\s11-steg13b\output\module\Omnicit.EntraRBAC\1.3.1.
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s1113b] Child process 0-1 ended with END: True
[oer-s1113b] IdentityTerms: 5
[oer-s1113b] AccountTermIsSignedInObject: True
[oer-s1113b] AccountChangedFlag: False
[oer-s1113b] SubscriptionsRead: True
[oer-s1113b] GroupsRead: 93
[oer-s1113b] Errors: []
[oer-s1113b] Requests: Graph 1, ARM 1, writes 0, token requests 0
```

### 0.2. A renewal as the same identity, -IncludeARM after a Microsoft Graph sign-in, and Connect-OER switching identity

- [x] **0.2** A renewal forced by moving `GraphTokenExpiry` into the five-minute window renews as oer-live-cc with one token request and no refusal, the identity unchanged and the ARM token kept; an ARM token acquired after a Graph-only `Connect-OER` is not refused; `Connect-OER` as oer-live-cc-noperm and back as oer-live-cc is not refused and moves the account term. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '0-2' -Body @'
Connect-OerLive -Arm
Start-S1113bFence
$M = Get-Module -Name Omnicit.EntraRBAC
$Before = [string](Get-S1113bIdentity)
$ArmBefore = [bool](Get-S1113bState).ArmToken
& $M { $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2) }
$Error.Clear()
Invoke-S1113bRenewal -ClientId $Cfg.AppId
$S = Get-S1113bState
$R.RenewalErrors = "[$(Get-S1113bIds $Error)]"
$R.RenewalTokenRequests = $global:Tokens
$R.RenewalIdentityUnchanged = ([string](Get-S1113bIdentity)) -ceq $Before
$R.RenewalExpiryMoved = $S.GraphTokenExpiry -gt [DateTime]::UtcNow.AddMinutes(30)
$R.RenewalArmKept = $ArmBefore -and [bool]$S.ArmToken
$R.RenewalAccountChangedFlag = [bool]$S.SignInAccountChanged
$Error.Clear()
$Groups = @(Get-OERGroup -Filter 'securityEnabled eq true' -ErrorAction SilentlyContinue)
$R.ReadAfterRenewal = "$($Groups.Count) groups; errors [$(Get-S1113bIds $Error)]"
Disconnect-OerLive
$Error.Clear(); $global:Tokens = 0
$null = Connect-OER -TenantId $T -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction SilentlyContinue
$R.GraphOnlyHoldsArm = [bool](Get-S1113bState).ArmToken
Invoke-S1113bRenewal -ClientId $Cfg.AppId -IncludeARM
$R.IncludeArmErrors = "[$(Get-S1113bIds $Error)]"
$R.IncludeArmTokenRequests = $global:Tokens
$R.IncludeArmAcquired = [bool](Get-S1113bState).ArmToken
$Error.Clear()
$Subs = @(Get-OERSubscription -ErrorAction SilentlyContinue)
$R.ReadAfterIncludeArm = "subscriptions read $($Subs.Count -gt 0); errors [$(Get-S1113bIds $Error)]"
$Error.Clear(); $global:Tokens = 0
$CcAccount = Get-S1113bTerm 4
$null = Connect-OER -TenantId $T -ClientId $Cfg.NoPermAppId -Certificate $Cert -ErrorAction SilentlyContinue
$NoPermAccount = Get-S1113bTerm 4
$null = Connect-OER -TenantId $T -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction SilentlyContinue
$R.SwitchErrors = "[$(Get-S1113bIds $Error)]"
$R.SwitchTokenRequests = $global:Tokens
$R.SwitchAccountTermMoved = [bool]$NoPermAccount -and ($NoPermAccount -cne $CcAccount)
$R.SwitchBackAccountTerm = (Get-S1113bTerm 4) -ceq $CcAccount
$R.SwitchAccountChangedFlag = [bool](Get-S1113bState).SignInAccountChanged
$Error.Clear()
$Groups = @(Get-OERGroup -Filter 'securityEnabled eq true' -ErrorAction SilentlyContinue)
$R.ReadAfterSwitch = "$($Groups.Count) groups; errors [$(Get-S1113bIds $Error)]"
$R.Writes = $global:Writes
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; renewal: no error, 1 token request, identity unchanged `True`, expiry moved `True`, ARM kept
`True`, flag `False`, then groups read with no error; `GraphOnlyHoldsArm: False`, then no error, 2 token requests
(the `Connect-OER` and the ARM token), ARM acquired `True`, subscriptions read with no error; the switch: no error,
2 token requests, account term moved `True`, back `True`, flag `False`, groups read with no error; 0 writes.
**Failure looks like:** `SignInSuperseded` on any line (a refusal of an ordinary run), or an ARM token not kept.

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113b] Child process 0-2 ended with END: True
[oer-s1113b] RenewalErrors: []
[oer-s1113b] RenewalTokenRequests: 1
[oer-s1113b] RenewalIdentityUnchanged: True
[oer-s1113b] RenewalExpiryMoved: True
[oer-s1113b] RenewalArmKept: True
[oer-s1113b] RenewalAccountChangedFlag: False
[oer-s1113b] ReadAfterRenewal: 93 groups; errors []
[oer-s1113b] GraphOnlyHoldsArm: False
[oer-s1113b] IncludeArmErrors: []
[oer-s1113b] IncludeArmTokenRequests: 2
[oer-s1113b] IncludeArmAcquired: True
[oer-s1113b] ReadAfterIncludeArm: subscriptions read True; errors []
[oer-s1113b] SwitchErrors: []
[oer-s1113b] SwitchTokenRequests: 2
[oer-s1113b] SwitchAccountTermMoved: True
[oer-s1113b] SwitchBackAccountTerm: True
[oer-s1113b] SwitchAccountChangedFlag: False
[oer-s1113b] ReadAfterSwitch: 93 groups; errors []
[oer-s1113b] Writes: 0
```

## 1. -TenantId binds the tenant, not the identity (BL-90)

### 1.1. Invoke-OERStructure -TenantId -WhatIf in an unchanged session plans and is not refused

- [x] **1.1** As oer-live-cc, `Invoke-OERStructure -TenantId` the test tenant `-WhatIf` with the minimal document plans its group and is not refused, sending reads only. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '1-1' -Body @'
Connect-OerLive -Arm
Start-S1113bFence
$Error.Clear()
$Rows = @(Invoke-OERStructure -TenantId $T -Json $Doc -WhatIf -ErrorAction SilentlyContinue)
$R.Rows = (@($Rows | ForEach-Object { '{0} {1}: {2} ({3})' -f $_.Section, $_.Item, $_.Action, $_.Detail }) -join '; ')
$R.Errors = "[$(Get-S1113bIds $Error)]"
$R.Requests = "Graph $global:Graph, writes $global:Writes, token requests $global:Tokens"
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; one row, `groups oer-s1113b-plan: Skipped (would create group oer-s1113b-plan)` -- the engine's
plan of a create under `-WhatIf`; `Errors: []`; at least one Graph read, 0 writes, 0 token requests.
**Failure looks like:** `SignInSuperseded` (a refusal of an ordinary run), a write, or a validation error of the
document.

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed on run 2. Run 1 stopped at the checklist, not the module: it expected a create action, and the engine plans a create under -WhatIf as a Skipped row "would create group"; the block now prints the row.
[oer-s1113b] Child process 1-1 ended with END: True
[oer-s1113b] Rows: groups oer-s1113b-plan: Skipped (would create group oer-s1113b-plan)
[oer-s1113b] Errors: []
[oer-s1113b] Requests: Graph 1, writes 0, token requests 0
```

### 1.2. The same command is refused when a later pipeline command signed in as another identity of the tenant

- [x] **1.2** In `Invoke-OERStructure -TenantId T -WhatIf | ForEach-Object -Begin { Connect-OER -TenantId T` as oer-live-cc-noperm `}`, the document is refused with `SignInSuperseded` (the document text), naming `Invoke-OERStructure`, and nothing is sent for it. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '1-2' -Body @'
Connect-OerLive -Arm
Start-S1113bFence
$CcAccount = Get-S1113bTerm 4
$Error.Clear()
$Rows = @(Invoke-OERStructure -TenantId $T -Json $Doc -WhatIf -ErrorAction SilentlyContinue |
    ForEach-Object -Begin { $null = Connect-OER -TenantId $T -ClientId $Cfg.NoPermAppId -Certificate $Cert -ErrorAction SilentlyContinue } -Process { $_ })
$R.Rows = $Rows.Count
$R.Errors = "[$(Get-S1113bIds $Error)]"
$R.Superseded = Get-S1113bSuperseded $Error
$R.SessionIsTheOtherIdentity = (Get-S1113bTerm 4) -cne $CcAccount
$R.Requests = "Graph $global:Graph, writes $global:Writes, token requests $global:Tokens"
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; 0 rows; `Errors: [SignInSuperseded x1]`; `Superseded: Invoke-OERStructure (document text)`; the
session is the other identity `True`; 0 Graph requests, 0 writes, 1 token request (the other identity's sign-in).
**Failure looks like:** planned rows or a Graph request (the defect: the document read under the other identity).

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113b] Child process 1-2 ended with END: True
[oer-s1113b] Rows: 0
[oer-s1113b] Errors: [SignInSuperseded x1]
[oer-s1113b] Superseded: Invoke-OERStructure (document text)
[oer-s1113b] SessionIsTheOtherIdentity: True
[oer-s1113b] Requests: Graph 0, writes 0, token requests 1
```

### 1.3. With no session when the command began, a later sign-in in the tenant refuses the document

- [x] **1.3** In a process with no session, `Invoke-OERStructure -TenantId T -WhatIf | ForEach-Object -Begin { Connect-OER -TenantId T` as oer-live-cc `}` refuses the document with `SignInSuperseded`, sending nothing for it. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '1-3' -Body @'
& (Get-Module -Name OerLive) { Import-OerLiveModule }
Start-S1113bFence
$R.NoSessionAtStart = $null -eq (Get-S1113bState)
$Error.Clear()
$Rows = @(Invoke-OERStructure -TenantId $T -Json $Doc -WhatIf -ErrorAction SilentlyContinue |
    ForEach-Object -Begin { $null = Connect-OER -TenantId $T -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction SilentlyContinue } -Process { $_ })
$R.Rows = $Rows.Count
$R.Errors = "[$(Get-S1113bIds $Error)]"
$R.Superseded = Get-S1113bSuperseded $Error
$R.Requests = "Graph $global:Graph, writes $global:Writes, token requests $global:Tokens"
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; `NoSessionAtStart: True`; 0 rows; `Errors: [SignInSuperseded x1]`;
`Superseded: Invoke-OERStructure (document text)`; 0 Graph requests, 0 writes, 1 token request.
**Failure looks like:** planned rows (the document taken the later sign-in's session for its own).

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113b] Child process 1-3 ended with END: True
[oer-s1113b] NoSessionAtStart: True
[oer-s1113b] Rows: 0
[oer-s1113b] Errors: [SignInSuperseded x1]
[oer-s1113b] Superseded: Invoke-OERStructure (document text)
[oer-s1113b] Requests: Graph 0, writes 0, token requests 1
```

### 1.4. A builder with -TenantId is refused the same way, and looks the name up without the switch

- [x] **1.4** `New-OERAccessPackageApprovalStage -TenantId T -User` a prefixed name piped into a `Connect-OER` as oer-live-cc-noperm in `-Begin` is refused with `SignInSuperseded` before any lookup; the same call as its own statement looks the name up (a Graph read) and reports the name as not found. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '1-4' -Body @'
Connect-OerLive -Arm
Start-S1113bFence
$Error.Clear()
$Stage = @(New-OERAccessPackageApprovalStage -TenantId $T -DurationDays 1 -User 'oer-s1113b-nobody' -ErrorAction SilentlyContinue |
    ForEach-Object -Begin { $null = Connect-OER -TenantId $T -ClientId $Cfg.NoPermAppId -Certificate $Cert -ErrorAction SilentlyContinue } -Process { $_ })
$R.PipedStages = $Stage.Count
$R.PipedErrors = "[$(Get-S1113bIds $Error)]"
$R.PipedSuperseded = Get-S1113bSuperseded $Error
$R.PipedGraph = $global:Graph
$null = Connect-OER -TenantId $T -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction SilentlyContinue
$Error.Clear(); $global:Graph = 0
$Stage = @(New-OERAccessPackageApprovalStage -TenantId $T -DurationDays 1 -User 'oer-s1113b-nobody' -ErrorAction SilentlyContinue)
$R.AloneStages = $Stage.Count
$R.AloneErrors = "[$(Get-S1113bIds $Error)]"
$R.AloneGraph = $global:Graph
$R.Writes = $global:Writes
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; piped: 0 stages, `[SignInSuperseded x1]` naming `New-OERAccessPackageApprovalStage`, 0 Graph
requests; alone: 0 stages, a not-found error id of the lookup and no `SignInSuperseded`, at least 1 Graph request;
0 writes.
**Failure looks like:** a Graph request in the piped call (the lookup under the other identity).

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed. The lookup of the name alone answers UserNotFound (the name matches no user), after one Graph read.
[oer-s1113b] Child process 1-4 ended with END: True
[oer-s1113b] PipedStages: 0
[oer-s1113b] PipedErrors: [SignInSuperseded x1]
[oer-s1113b] PipedSuperseded: New-OERAccessPackageApprovalStage
[oer-s1113b] PipedGraph: 0
[oer-s1113b] AloneStages: 0
[oer-s1113b] AloneErrors: [UserNotFound x1]
[oer-s1113b] AloneGraph: 1
[oer-s1113b] Writes: 0
```

### 1.5. A command naming the tenant differently from the session is not refused by BL-90: it signs in itself

- [x] **1.5** `Invoke-OERStructure -TenantId` the tenant's domain (the session names it by tenant ID) in the same pipeline as 1.2 is not refused with `SignInSuperseded`; it signs in itself, which the fence refuses, since that sign-in would be interactive. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '1-5' -Body @'
Connect-OerLive -Arm
Start-S1113bFence
$Error.Clear()
$Rows = @(Invoke-OERStructure -TenantId $Cfg.Domain -Json $Doc -WhatIf -ErrorAction SilentlyContinue |
    ForEach-Object -Begin { $null = Connect-OER -TenantId $T -ClientId $Cfg.NoPermAppId -Certificate $Cert -ErrorAction SilentlyContinue } -Process { $_ })
$R.Rows = (@($Rows | ForEach-Object { '{0} {1}: {2}' -f $_.Section, $_.Item, $_.Action }) -join '; ')
$R.Errors = "[$(Get-S1113bIds $Error)]"
$R.Superseded = Get-S1113bSuperseded $Error
$R.Requests = "Graph $global:Graph, writes $global:Writes, token requests $global:Tokens"
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; no `SignInSuperseded`; `GraphTokenAcquisitionFailed x1` (the fence refused the interactive token
request) and `SignInRefused` for the latched command's refused read; at most one row, for the group, which is not a
plan (`Failed`: the command carries on past its refused sign-in and sends nothing); 0 Graph requests, 0 writes, 2
token requests (the other identity's sign-in and the refused one).
**Failure looks like:** `SignInSuperseded` (BL-90 refusing a command that does not inherit the session), a Graph
request, or a `Skipped (would create ...)` plan row.

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed on run 2. Run 1 showed the same refusals and requests; the checklist expected 0 rows, and the latched command carries on past its refused sign-in and reports its group Failed, sending nothing (existing behaviour). The block now prints the row.
[oer-s1113b] Child process 1-5 ended with END: True
[oer-s1113b] Rows: groups oer-s1113b-plan: Failed
[oer-s1113b] Errors: [GraphTokenAcquisitionFailed x1, SignInRefused x1]
[oer-s1113b] Superseded: 
[oer-s1113b] Requests: Graph 0, writes 0, token requests 2
```

## 2. A sign-in nested under a superseded command (BL-91 b)

### 2.1. The second Connect-OER inside a superseded command's output is refused before any token request

- [x] **2.1** In `Get-OERRoleDefinition -Subscription S -TenantId T | Select-Object -First 2 | ForEach-Object { Connect-OER ... }`, the first `Connect-OER` (oer-live-cc-noperm) signs in and supersedes `Get-OERRoleDefinition`; the second (oer-live-cc) is refused with `SignInSuperseded` naming `Get-OERRoleDefinition`, with no token request. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '2-1' -Body @'
Connect-OerLive -Arm
Start-S1113bFence
$Error.Clear()
$script:Item = 0
$Counts = @(Get-OERRoleDefinition -Subscription $Cfg.SubscriptionId -TenantId $T -ErrorAction SilentlyContinue | Select-Object -First 2 | ForEach-Object {
    $script:Item++
    $App = if ($script:Item -eq 1) { $Cfg.NoPermAppId } else { $Cfg.AppId }
    $null = Connect-OER -TenantId $T -ClientId $App -Certificate $Cert -ErrorAction SilentlyContinue
    $global:Tokens
})
$R.ItemsHandled = $script:Item
$R.TokenRequestsAfterEachItem = $Counts -join ','
$R.Errors = "[$(Get-S1113bIds $Error)]"
$R.Superseded = Get-S1113bSuperseded $Error
$R.Writes = $global:Writes
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; 2 items handled; token requests `1,1` (the first sign-in only); `[SignInSuperseded x1]`;
`Superseded: Get-OERRoleDefinition`; 0 writes.
**Failure looks like:** token requests `1,2` (the nested sign-in reached `Get-AzToken`), or no refusal.

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113b] Child process 2-1 ended with END: True
[oer-s1113b] ItemsHandled: 2
[oer-s1113b] TokenRequestsAfterEachItem: 1,1
[oer-s1113b] Errors: [SignInSuperseded x1]
[oer-s1113b] Superseded: Get-OERRoleDefinition
[oer-s1113b] Writes: 0
```

### 2.2. A nested read under an unchanged session is not refused

- [x] **2.2** In `Get-OERRoleDefinition -Subscription S -TenantId T | Select-Object -First 2 | ForEach-Object { Get-OERGroup ... }`, both nested reads run with no error and no token request. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '2-2' -Body @'
Connect-OerLive -Arm
Start-S1113bFence
$Error.Clear()
$Counts = @(Get-OERRoleDefinition -Subscription $Cfg.SubscriptionId -TenantId $T -ErrorAction SilentlyContinue | Select-Object -First 2 | ForEach-Object {
    @(Get-OERGroup -Filter 'securityEnabled eq true' -ErrorAction SilentlyContinue).Count -gt 0
})
$R.NestedReads = $Counts -join ','
$R.Errors = "[$(Get-S1113bIds $Error)]"
$R.Requests = "Graph $global:Graph, ARM $global:Arm, writes $global:Writes, token requests $global:Tokens"
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; `NestedReads: True,True`; `Errors: []`; at least 2 Graph and 1 ARM requests, 0 writes, 0 token
requests.
**Failure looks like:** `SignInSuperseded` (a refusal of an ordinary nested read).

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113b] Child process 2-2 ended with END: True
[oer-s1113b] NestedReads: True,True
[oer-s1113b] Errors: []
[oer-s1113b] Requests: Graph 2, ARM 1, writes 0, token requests 0
```

## 3. A renewal never continues as another account (BL-119)

Both checks move the session's `SignedInObjectId` in module scope to a random GUID that names nobody, so the real
token of `oer-live-cc` is "another account" than the session's. Nothing is sent to the tenant for it.

### 3.1. A Microsoft Graph renewal answered by another account is refused, and the session then needs Connect-OER

- [x] **3.1** With the session's object id moved and its Graph token in the renewal window, the renewal is refused with `SignInSuperseded` (the account text) after one token request; the session is then the token's account with the flag on and no ARM token; a read naming no tenant is refused (`SignInRefused`) and sends nothing; a bare `Connect-OER` answers from that session and keeps the flag, `Connect-OER -Force` signs in again and clears it, and a read follows. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '3-1' -Body @'
Connect-OerLive -Arm
Start-S1113bFence
$M = Get-Module -Name Omnicit.EntraRBAC
$Real = [string](Get-S1113bState).SignedInObjectId
& $M { param($F) $script:_OERAuthState.SignedInObjectId = $F; $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2) } ([guid]::NewGuid().ToString())
$Error.Clear()
Invoke-S1113bRenewal -ClientId $Cfg.AppId
$S = Get-S1113bState
$R.RenewalErrors = "[$(Get-S1113bIds $Error)]"
$R.RenewalSuperseded = Get-S1113bSuperseded $Error
$R.RenewalTokenRequests = $global:Tokens
$R.SessionIsTheTokensAccount = [bool]$Real -and ([string]$S.SignedInObjectId -ceq $Real) -and ((Get-S1113bTerm 4) -ceq $Real)
$R.AccountChangedFlag = [bool]$S.SignInAccountChanged
$R.ArmTokenDropped = -not [bool]$S.ArmToken
$Error.Clear(); $global:Graph = 0
$Groups = @(Get-OERGroup -Filter 'securityEnabled eq true' -ErrorAction SilentlyContinue)
$R.ReadNamingNoTenant = "$($Groups.Count) groups; errors [$(Get-S1113bIds $Error)]; Graph $global:Graph"
$Error.Clear(); $global:Graph = 0; $global:Tokens = 0
$null = Connect-OER -TenantId $T -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction SilentlyContinue
$R.BareConnect = "token requests $global:Tokens; flag $([bool](Get-S1113bState).SignInAccountChanged)"
$global:Tokens = 0
$null = Connect-OER -TenantId $T -ClientId $Cfg.AppId -Certificate $Cert -Force -ErrorAction SilentlyContinue
$R.ForceConnect = "token requests $global:Tokens; flag $([bool](Get-S1113bState).SignInAccountChanged)"
$Groups = @(Get-OERGroup -Filter 'securityEnabled eq true' -ErrorAction SilentlyContinue)
$R.ReadAfterConnect = "$($Groups.Count -gt 0); errors [$(Get-S1113bIds $Error)]"
$R.Writes = $global:Writes
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; `[SignInSuperseded x1]`, `a script block (account text)` (the renewal's caller here is the
module-scope script block); 1 token request; the session is the token's account `True`; flag `True`; ARM token
dropped `True`; the read naming no tenant: 0 groups, `SignInRefused` (and no `SignInSuperseded`), 0 Graph requests;
a bare `Connect-OER`: 0 token requests and the flag still `True` (it answers from the session the renewal left,
which is why the advice is `Connect-OER -Force`); `Connect-OER -Force`: 1 token request, flag `False`; groups read,
no error; 0 writes.
**Failure looks like:** no refusal (the renewal continued as another account), an ARM token kept, or a Graph request
from the read naming no tenant.

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed on run 2. Run 1 showed every refusal as expected; its last step expected a bare Connect-OER to clear the account flag, but a bare Connect-OER answers from the session the refused renewal left (0 token requests, flag kept), which is why the advice is Connect-OER -Force. The block now runs both.
[oer-s1113b] Child process 3-1 ended with END: True
[oer-s1113b] RenewalErrors: [SignInSuperseded x1]
[oer-s1113b] RenewalSuperseded: a script block (account text)
[oer-s1113b] RenewalTokenRequests: 1
[oer-s1113b] SessionIsTheTokensAccount: True
[oer-s1113b] AccountChangedFlag: True
[oer-s1113b] ArmTokenDropped: True
[oer-s1113b] ReadNamingNoTenant: 0 groups; errors [SignInRefused x2]; Graph 0
[oer-s1113b] BareConnect: token requests 0; flag True
[oer-s1113b] ForceConnect: token requests 1; flag False
[oer-s1113b] ReadAfterConnect: True; errors []
[oer-s1113b] Writes: 0
```

### 3.2. A renewal's ARM token of another account is refused and not cached

- [x] **3.2** After a Graph-only `Connect-OER` and with the session's object id moved, an `-IncludeARM` renewal is refused with `SignInSuperseded` (the account text) after one token request (the ARM one), no ARM token is cached, and the session's object id is left as it was. #type/subtask

```powershell
$Res = Invoke-S1113bBlock -Name '3-2' -Body @'
& (Get-Module -Name OerLive) { Import-OerLiveModule }
Start-S1113bFence
$null = Connect-OER -TenantId $T -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction SilentlyContinue
$M = Get-Module -Name Omnicit.EntraRBAC
$Fake = [guid]::NewGuid().ToString()
& $M { param($F) $script:_OERAuthState.SignedInObjectId = $F } $Fake
$Error.Clear(); $global:Tokens = 0
Invoke-S1113bRenewal -ClientId $Cfg.AppId -IncludeARM
$S = Get-S1113bState
$R.Errors = "[$(Get-S1113bIds $Error)]"
$R.Superseded = Get-S1113bSuperseded $Error
$R.TokenRequests = $global:Tokens
$R.ArmTokenCached = [bool]$S.ArmToken
$R.ObjectIdLeftAsItWas = [string]$S.SignedInObjectId -ceq $Fake
$R.AccountChangedFlag = [bool]$S.SignInAccountChanged
$R.Writes = $global:Writes
Disconnect-OerLive
'@
Write-S1113bResult $Res
```

**Expect:** `END`; `[SignInSuperseded x1]`, `a script block (account text)`; 1 token request; ARM token cached
`False`; object id left `True`; flag `False`; 0 writes.
**Failure looks like:** an ARM token cached (another account's token under the session's identity).

Result: 2026-10-22 08:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113b] Child process 3-2 ended with END: True
[oer-s1113b] Errors: [SignInSuperseded x1]
[oer-s1113b] Superseded: a script block (account text)
[oer-s1113b] TokenRequests: 1
[oer-s1113b] ArmTokenCached: False
[oer-s1113b] ObjectIdLeftAsItWas: True
[oer-s1113b] AccountChangedFlag: False
[oer-s1113b] Writes: 0
```

## B. Proved offline (class B)

- **B.1** The outer frames that remember the old account are refused after an account change (by the transports and
  by the nested-sign-in check), the caller stays latched and the session uncertain, a transport's forced refresh is a
  renewal, and `Connect-OER` is never refused by it: `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, the BL-119
  Describe.
- **B.2** A token without an object id, on either side, never refuses anything and never moves the identity's
  account term: the same Describe, and `tests/Unit/Private/Get-OERSignInIdentity.Tests.ps1`.
- **B.3** The order of the refusals at a sign-in's entry (BL-74 before BL-91 b), and that neither latches the caller
  nor changes the session-uncertain marker: `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, the BL-91 Context,
  and `tests/Unit/Private/Get-OERSignInSupersession.Tests.ps1`.
- **B.4** The BL-90 compare in the three builders and in `Invoke-OERStructure` for every session shape (another
  identity of the tenant, none then and one now, another tenant, a tenant named differently, unchanged), and the
  owner `Test-OERSessionUsable`: their test files.

## C. Manual (class C, optional, after the merge)

- [ ] **C.1** The operator signs in interactively (`Connect-OER -TenantId` the test tenant), moves `GraphTokenExpiry` into the five-minute window in module scope, runs `Get-OERGroup`, and answers the account picker with ANOTHER account of the tenant: the command is refused with `SignInSuperseded` (the account text) and sends nothing; a following `Get-OERGroup` is refused (`SignInRefused`) until `Connect-OER`. #type/subtask

Result:

## T. Teardown

### T.1. The step's raw folder is gone, and nothing was created in the tenant

- [x] **T.1** The raw folder `raw\s1113b\` (child scripts, results, logs) is deleted, and no object with the prefix exists in the tenant. #type/subtask

```powershell
Connect-OerLive -Arm
$Found = Invoke-OerLiveGraph -All -Uri "v1.0/groups?`$filter=startswith(displayName,'$Prefix')&`$select=id"
Write-OerLiveStep "Groups with the prefix: $(@($Found.Body['value']).Count)"
Disconnect-OerLive
Remove-Item -LiteralPath $Raw -Recurse -Force
Write-OerLiveStep "Raw folder gone: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** 0 groups with the prefix; `Raw folder gone: True`.
**Failure looks like:** a prefixed object (STOP: this file creates none) or the folder still there.

Result: 2026-10-22 08:19 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113b] Omnicit.EntraRBAC 1.3.1 loaded from REPO\.claude\worktrees\s11-steg13b\output\module\Omnicit.EntraRBAC\1.3.1.
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s1113b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s1113b] Groups with the prefix: 0
[oer-s1113b] Raw folder gone: True
```
