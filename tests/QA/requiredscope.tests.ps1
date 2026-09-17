BeforeDiscovery {
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    <#
        If the QA tests are run outside of the build script (e.g with Invoke-Pester)
        the parent scope has not set the variable $ProjectName.
    #>
    if (-not $ProjectName)
    {
        # Assuming project folder name is project name.
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    <#
        Discovery reads the manifest off disk and needs no loaded module, so there is deliberately
        no Import-Module or Remove-Module here. Pester v5 discovers EVERY file before running any,
        so unloading the module at discovery would reach into other files' run phase.
    #>
    $script:exportedForCases = (Import-PowerShellDataFile -Path (
            Join-Path -Path $projectPath -ChildPath 'source' |
                Join-Path -ChildPath ('{0}.psd1' -f $script:moduleName))).FunctionsToExport

    # One case per exported cmdlet so a failure names the offender instead of dumping the table.
    $script:cmdletCases = @($script:exportedForCases | ForEach-Object { @{ Name = $_ } })
}

BeforeAll {
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    if (-not $ProjectName)
    {
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName
    $script:sourcePath = Join-Path -Path $projectPath -ChildPath 'source'

    $script:exportedNames = (Import-PowerShellDataFile -Path (
            Join-Path -Path $script:sourcePath -ChildPath ('{0}.psd1' -f $script:moduleName))).FunctionsToExport

    <#
        Import here rather than relying on an already-loaded module. tests/QA/module.tests.ps1
        sorts before this file and its 'Should remove without error' test calls Remove-Module, so
        by the time this BeforeAll runs there may be no loaded module to reach into -- which
        yields an EMPTY table and fails every case below for the wrong reason.
    #>
    $script:mut = Get-Module -Name $script:moduleName -ListAvailable |
        Select-Object -First 1 |
            Import-Module -Force -ErrorAction Stop -PassThru

    $script:table = @(& $script:mut { Get-OERRequiredScopeMap })

    $script:table.Count | Should -BeGreaterThan 0 -Because (
        'the table must be readable from the built module; an empty one would pass the per-cmdlet cases vacuously')

    $script:entryByName = @{}
    foreach ($Entry in $script:table) { $script:entryByName[$Entry.Cmdlet] = $Entry }

    <#
        =====================================================================================
        Re-derive the call graph from source, independently of the shipped table.

        Three things this has to get right, each of which a simpler reading gets wrong:

        1. TRANSITIVE. A public cmdlet's requirement is the union of its own transport calls and
           every call its private helpers make. Add-OERAdministrativeUnitScopedRole reaches
           POST v1.0/directoryRoles only through Resolve-OERDirectoryRoleId. A per-file grep of
           source/Public finds 51 Graph cmdlets; the correct answer is 70.

        2. INDIRECT DISPATCH. Invoke-OERStructure calls its handlers as
           `& $Section.Handler`, where Handler is a STRING. A CommandAst-only walk reports it
           offline. String constants naming a module function therefore count as call edges.
           Comment-based help is a COMMENT token and never an AST expression, so
           Test-OERStructure -- whose only Get-OERInventory mentions are in its help block --
           correctly stays offline without a special case.

        3. TRANSPORT COMES FROM THE CALL GRAPH, NOT FROM URI LITERALS. An ARM path is often
           "$Id`?api-version=..." with the whole scope inside the variable, so no literal in the
           file reveals the call at all; Set-OERRoleAssignment and Remove-OERRoleAssignment are
           invisible to a literal scan. Graph literals ARE reliable -- anchored on v1.0/ or beta/,
           except the PIM-for-Groups paths, whose version prefix Get-OERPimGroupsGraphPath owns, so
           they are anchored on their two resource roots instead (see the GraphUri block below)
           and are used only for the endpoint-linkage assertion.
        =====================================================================================
    #>
    $script:functionAst = @{}
    $script:allFunctions = [System.Collections.Generic.HashSet[string]]::new()
    $script:privateFunctions = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($File in @(Get-ChildItem -Path (Join-Path $script:sourcePath 'Public') -Filter '*.ps1') +
        @(Get-ChildItem -Path (Join-Path $script:sourcePath 'Private') -Filter '*.ps1'))
    {
        $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)

        # Top-level definition only: a nested helper is part of its parent's body, not its own node.
        $Definition = $FileAst.FindAll({
                param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $false) | Select-Object -First 1

        if ($Definition)
        {
            $script:functionAst[$Definition.Name] = $Definition
            $null = $script:allFunctions.Add($Definition.Name)
            if ($File.Directory.Name -eq 'Private') { $null = $script:privateFunctions.Add($Definition.Name) }
        }
    }

    function Get-MethodArgument
    {
        param($Command)

        $Elements = $Command.CommandElements
        for ($Index = 1; $Index -lt $Elements.Count; $Index++)
        {
            $Element = $Elements[$Index]
            if ($Element -is [System.Management.Automation.Language.CommandParameterAst] -and
                $Element.ParameterName -eq 'Method')
            {
                $Value = $Element.Argument
                if ($null -eq $Value -and ($Index + 1) -lt $Elements.Count) { $Value = $Elements[$Index + 1] }
                if ($Value.Value) { return ([string]$Value.Value).ToUpperInvariant() }
            }
        }

        # Invoke-OERGraphRequest and Invoke-OERArmRequest both default -Method to GET.
        return 'GET'
    }

    $script:localFacts = @{}
    $script:callEdges = @{}

    foreach ($Name in $script:allFunctions)
    {
        $Definition = $script:functionAst[$Name]

        $Commands = $Definition.FindAll({
                param($Node) $Node -is [System.Management.Automation.Language.CommandAst]
            }, $true)

        $Strings = $Definition.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                $Node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
            }, $true)

        $Edges = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Command in $Commands)
        {
            $CommandName = $Command.GetCommandName()
            if ($CommandName -and $script:allFunctions.Contains($CommandName)) { $null = $Edges.Add($CommandName) }
        }
        <#
            Indirect dispatch, but only to PRIVATE functions. Invoke-OERStructure's handler table
            holds strings such as 'Sync-OERStructureGroup' that it later invokes with `& `. Counting
            EVERY module-function name found in a string would misread a data table that merely
            lists cmdlet names -- Get-OERRequiredScopeMap names all 89 of them -- as calling them.
            Nothing in this module dispatches indirectly to a public cmdlet.
        #>
        foreach ($String in $Strings)
        {
            if ($script:privateFunctions.Contains($String.Value)) { $null = $Edges.Add($String.Value) }
        }
        $script:callEdges[$Name] = $Edges

        $Transports = foreach ($Command in $Commands)
        {
            $CommandName = $Command.GetCommandName()
            if ($CommandName -in 'Invoke-OERGraphRequest', 'Invoke-OERArmRequest')
            {
                [PSCustomObject]@{
                    Transport = if ($CommandName -eq 'Invoke-OERGraphRequest') { 'Graph' } else { 'Arm' }
                    Method    = Get-MethodArgument -Command $Command
                }
            }
        }
        $Transports = @($Transports)

        $GraphWrites = [bool]@($Transports | Where-Object { $_.Transport -eq 'Graph' -and $_.Method -ne 'GET' }).Count

        $script:localFacts[$Name] = [PSCustomObject]@{
            CallsGraph = [bool]@($Transports | Where-Object Transport -EQ 'Graph').Count
            CallsArm   = [bool]@($Transports | Where-Object Transport -EQ 'Arm').Count
            # Paired here so the write flag stays attached to the function that owns the literal.
            # Add-OERGroupMember POSTs to /groups/{id}/members and transitively GETs /users through
            # Resolve-OERUserId; a chain-wide flag would promote that read to User.ReadWrite.All.
            GraphUri   = @(foreach ($String in $Strings)
                {
                    <#
                        Graph URI literals are anchored on the API version, with one deliberate
                        exception: the PIM-for-Groups paths no longer carry their version at the
                        call site because Get-OERPimGroupsGraphPath owns the pin (see its
                        .DESCRIPTION). Those literals start at the resource instead, so they are
                        anchored on their two resource roots. They stay attached to the CALLING
                        function, not to the helper, which is what keeps the write flag correct --
                        the helper itself makes no Graph call and would mark every path a read.
                    #>
                    if ($String.Value -match '^(v1\.0|beta)/' -or
                        $String.Value -match '^(identityGovernance/privilegedAccess/group|policies/roleManagementPolic)')
                    {
                        [PSCustomObject]@{ Uri = $String.Value; Write = $GraphWrites; Owner = $Name }
                    }
                })
        }
    }

    $script:closureCache = @{}
    function Resolve-CallClosure
    {
        param([string]$Name, [System.Collections.Generic.HashSet[string]]$Visiting)

        if ($script:closureCache.ContainsKey($Name)) { return $script:closureCache[$Name] }
        if ($Visiting.Contains($Name)) { return [System.Collections.Generic.HashSet[string]]::new() }
        $null = $Visiting.Add($Name)

        $Reached = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Callee in $script:callEdges[$Name])
        {
            $null = $Reached.Add($Callee)
            foreach ($Deep in (Resolve-CallClosure -Name $Callee -Visiting $Visiting)) { $null = $Reached.Add($Deep) }
        }

        $null = $Visiting.Remove($Name)
        $script:closureCache[$Name] = $Reached
        return $Reached
    }

    $script:derived = @{}
    foreach ($Name in $script:exportedNames)
    {
        if (-not $script:allFunctions.Contains($Name)) { continue }

        $Chain = @($Name) + @(Resolve-CallClosure -Name $Name -Visiting ([System.Collections.Generic.HashSet[string]]::new()))
        $ReachesGraph = [bool]@($Chain | Where-Object { $script:localFacts[$_].CallsGraph }).Count
        $ReachesArm = [bool]@($Chain | Where-Object { $script:localFacts[$_].CallsArm }).Count

        $script:derived[$Name] = [PSCustomObject]@{
            Transport = if ($ReachesGraph -and $ReachesArm) { 'GraphAndArm' }
            elseif ($ReachesGraph) { 'Graph' }
            elseif ($ReachesArm) { 'Arm' }
            else { 'None' }
            GraphUri  = @(foreach ($Link in $Chain) { $script:localFacts[$Link].GraphUri })
        }
    }

    <#
        =====================================================================================
        The endpoint -> permission map.

        Deliberately small and deliberately stable. Graph's permission for a given resource path
        changes rarely, while cmdlets are added all the time -- so the map is the part that stays
        put and the table is the part that gets gated against it. Each entry says: any cmdlet that
        reaches this endpoint MUST declare a permission matching Read (or Write, when the owning
        function uses a write method).

        NotMatch on the administrativeUnits entry matters. A POST to
        /directory/administrativeUnits/{id}/scopedRoleMembers contains the administrativeUnits
        path but writes DIRECTORY ROLE MEMBERSHIP, not unit membership -- Microsoft Learn asks
        only for RoleManagement.ReadWrite.Directory there. Without the exclusion this entry would
        also demand AdministrativeUnit.ReadWrite.All, which is more than the API needs.

        Every pattern below was confirmed against a published Microsoft Learn permissions table.
        =====================================================================================
    #>
    $script:endpointMap = @(
        @{
            Endpoint = 'directory/administrativeUnits/*/scopedRoleMembers'
            Match    = '/scopedRoleMembers'
            Read     = '^RoleManagement\.(Read|ReadWrite)\.Directory$'
            Write    = '^RoleManagement\.ReadWrite\.Directory$'
        }
        @{
            Endpoint = 'directoryRoles, directoryRoleTemplates'
            Match    = 'v1.0/directoryRole'
            Read     = '^RoleManagement\.(Read|ReadWrite)\.Directory$'
            Write    = '^RoleManagement\.ReadWrite\.Directory$'
        }
        @{
            Endpoint = 'directory/administrativeUnits'
            Match    = 'directory/administrativeUnits'
            NotMatch = '/scopedRoleMembers'
            Read     = '^AdministrativeUnit\.(Read|ReadWrite)\.All$'
            Write    = '^AdministrativeUnit\.ReadWrite\.All$'
        }
        @{
            Endpoint = 'identityGovernance/entitlementManagement/*'
            Match    = 'identityGovernance/entitlementManagement'
            Read     = '^EntitlementManagement\.(Read|ReadWrite)\.All$'
            Write    = '^EntitlementManagement\.ReadWrite\.All$'
        }
        @{
            Endpoint = 'identity/conditionalAccess/authenticationContextClassReferences'
            Match    = 'identity/conditionalAccess'
            Read     = '^(AuthenticationContext\.(Read|ReadWrite)\.All|Policy\.(Read|ReadWrite)\.ConditionalAccess)$'
            Write    = '^(AuthenticationContext\.ReadWrite\.All|Policy\.ReadWrite\.ConditionalAccess)$'
        }
        @{
            Endpoint = 'identityGovernance/accessReviews/*'
            Match    = 'identityGovernance/accessReviews'
            Read     = '^AccessReview\.(Read|ReadWrite)\.All$'
            Write    = '^AccessReview\.ReadWrite\.All$'
        }
        @{
            Endpoint = 'identityGovernance/privilegedAccess/group/*'
            Match    = 'privilegedAccess/group'
            Read     = '^PrivilegedEligibilitySchedule\.(Read|ReadWrite)\.AzureADGroup$'
            Write    = '^PrivilegedEligibilitySchedule\.ReadWrite\.AzureADGroup$'
        }
        @{
            Endpoint = 'policies/roleManagementPolicies*'
            Match    = 'policies/roleManagementPolic'
            Read     = '^RoleManagementPolicy\.(Read|ReadWrite)\.AzureADGroup$'
            Write    = '^RoleManagementPolicy\.ReadWrite\.AzureADGroup$'
        }
        @{
            Endpoint = 'groups'
            Match    = 'v1.0/groups'
            Read     = '^(Group\.(Read|ReadWrite)\.All|Directory\.Read(Write)?\.All)$'
            Write    = '^(Group\.ReadWrite\.All|Directory\.ReadWrite\.All)$'
        }
        @{
            Endpoint = 'users'
            Match    = 'v1.0/users'
            Read     = '^(User\.(ReadBasic|Read|ReadWrite)\.All|Directory\.Read(Write)?\.All)$'
            Write    = '^(User\.ReadWrite\.All|Directory\.ReadWrite\.All)$'
        }
        @{
            Endpoint = 'servicePrincipals'
            Match    = 'v1.0/servicePrincipals'
            Read     = '^(Application\.(Read|ReadWrite)\.All|Directory\.Read(Write)?\.All)$'
            Write    = '^(Application\.ReadWrite\.All|Directory\.ReadWrite\.All)$'
        }
        @{
            <#
                getByIds is a READ expressed as a POST, so the write pattern deliberately equals
                the read one: Microsoft Learn asks for Directory.Read.All on both
                GET /directoryObjects/{id} and POST /directoryObjects/getByIds. Deriving the
                permission from the HTTP verb alone would demand Directory.ReadWrite.All here,
                which is a real privilege escalation in the consent list this table produces.
            #>
            Endpoint = 'directoryObjects, directoryObjects/getByIds'
            Match    = 'v1.0/directoryObjects'
            Read     = '^Directory\.Read(Write)?\.All$'
            Write    = '^Directory\.Read(Write)?\.All$'
        }
    )
}

Describe 'Required scope table' -Tags 'helpQuality' {
    Context 'Completeness' {
        It 'Should hold an entry for every exported cmdlet' {
            $missing = @($script:exportedNames | Where-Object { -not $script:entryByName.ContainsKey($_) })

            $missing | Should -BeNullOrEmpty -Because (
                'Get-OERRequiredScopeMap is the consent list handed to a customer, so a cmdlet with no entry is an unanswerable question; missing: {0}' -f (
                    $missing -join ', '))
        }

        It 'Should not hold an entry for anything that is not exported' {
            $orphan = @($script:table.Cmdlet | Where-Object { $_ -notin $script:exportedNames })

            $orphan | Should -BeNullOrEmpty -Because (
                'an entry for a cmdlet that no longer exists is stale documentation that looks authoritative; orphans: {0}' -f (
                    $orphan -join ', '))
        }

        It 'Should name each cmdlet exactly once' {
            $duplicate = @($script:table | Group-Object Cmdlet | Where-Object Count -GT 1)

            $duplicate | Should -BeNullOrEmpty -Because (
                'a duplicated entry makes -Unique ambiguous; duplicated: {0}' -f ($duplicate.Name -join ', '))
        }
    }

    Context 'Transport agrees with the source' {
        It 'Should declare the transport <Name> actually reaches' -ForEach $script:cmdletCases {
            $entry = $script:entryByName[$Name]
            $entry | Should -Not -BeNullOrEmpty -Because ('{0} must have a scope entry' -f $Name)

            $expected = $script:derived[$Name].Transport

            $entry.Transport | Should -Be $expected -Because (
                '{0} transitively reaches {1}; the table says {2}. A cmdlet that starts calling Graph or ARM must gain the matching permissions.' -f
                    $Name, $expected, $entry.Transport)
        }
    }

    Context 'Declared permissions cover the endpoints actually called' {
        It 'Should declare a permission matching every endpoint <Name> reaches' -ForEach $script:cmdletCases {
            $entry = $script:entryByName[$Name]
            $entry | Should -Not -BeNullOrEmpty -Because ('{0} must have a scope entry' -f $Name)

            $declared = @($entry.GraphScope)
            $failures = [System.Collections.Generic.List[string]]::new()

            foreach ($Call in $script:derived[$Name].GraphUri)
            {
                foreach ($Rule in $script:endpointMap)
                {
                    if ($Call.Uri -notlike ('*{0}*' -f $Rule.Match)) { continue }
                    if ($Rule.NotMatch -and $Call.Uri -like ('*{0}*' -f $Rule.NotMatch)) { continue }

                    $required = if ($Call.Write) { $Rule.Write } else { $Rule.Read }

                    if (-not @($declared | Where-Object { $_ -match $required }).Count)
                    {
                        $failures.Add(('{0} (via {1}, {2}) needs a permission matching {3}' -f
                                $Rule.Endpoint, $Call.Owner, $(if ($Call.Write) { 'writes' } else { 'reads' }), $required))
                    }
                }
            }

            $unique = @($failures | Sort-Object -Unique)

            $unique | Should -BeNullOrEmpty -Because (
                'Graph grants permissions by the resource a call touches, so {0} must declare one for each endpoint it reaches -- including through its private helpers. Declared: {1}. Unsatisfied: {2}' -f
                    $Name, ($declared -join ', '), ($unique -join ' | '))
        }
    }
}
