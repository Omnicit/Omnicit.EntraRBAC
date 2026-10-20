BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERApproverErrorClass' {
    # Pure: the class comes from the record's FullyQualifiedErrorId alone. Each record is built with the
    # id as given, so a bare id stands for the record as thrown and an id with ',<command>' for one that
    # has already crossed a WriteError boundary.
    It 'classifies <Id> as <Class>' -ForEach @(
        @{ Id = 'AmbiguousName'; Class = 'Ambiguous' }
        @{ Id = 'AmbiguousName,Resolve-OERGroupId'; Class = 'Ambiguous' }
        @{ Id = 'ApproverUnresolved'; Class = 'NotFound' }
        @{ Id = 'ApproverUnresolved,Resolve-OERApproverInput'; Class = 'NotFound' }
        @{ Id = 'PrincipalUnresolved'; Class = 'NotFound' }
        @{ Id = 'PrincipalUnresolved,Resolve-OERPrincipal'; Class = 'NotFound' }
        @{ Id = 'Authorization_RequestDenied'; Class = 'Other' }
        @{ Id = 'GraphServiceUnavailable,Invoke-OERGraphRequest'; Class = 'Other' }
        # The published ids are not the internal ones: a record already reported is never re-read as one.
        @{ Id = 'ApproverNotFound'; Class = 'Other' }
        @{ Id = 'AmbiguousApproverName'; Class = 'Other' }
        @{ Id = 'PrincipalNotFound'; Class = 'Other' }
        # Ordinal and a prefix: another letter case, or the id later in the text, is not the id.
        @{ Id = 'approverunresolved'; Class = 'Other' }
        @{ Id = 'PRINCIPALUNRESOLVED'; Class = 'Other' }
        @{ Id = 'XApproverUnresolved'; Class = 'Other' }
        @{ Id = 'Lookup,PrincipalUnresolved'; Class = 'Other' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Id = $Id; Class = $Class } {
            param($Id, $Class)
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('lookup answer'), $Id, [System.Management.Automation.ErrorCategory]::NotSpecified, 'value')
            $Answer = Get-OERApproverErrorClass -Record $Record
            $Answer | Should -BeOfType ([string])
            $Answer | Should -BeExactly $Class
        }
    }

    It 'classifies a record caught from a throw the way the approver resolvers throw it' {
        # The shape every site sees: the ErrorRecord thrown by the resolver, caught as $PSItem.
        InModuleScope Omnicit.EntraRBAC {
            $Caught = $null
            try {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Group 'missing-approvers' was not found."), 'ApproverUnresolved',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'missing-approvers')
            } catch {
                $Caught = $PSItem
            }
            Get-OERApproverErrorClass -Record $Caught | Should -BeExactly 'NotFound'
        }
    }

    It 'answers Other for a null record, and never throws' {
        InModuleScope Omnicit.EntraRBAC {
            { Get-OERApproverErrorClass -Record $null } | Should -Not -Throw
            Get-OERApproverErrorClass -Record $null | Should -BeExactly 'Other'
            Get-OERApproverErrorClass | Should -BeExactly 'Other'
        }
    }

    It 'asks Test-OERAmbiguousNameError, the owner of the ambiguity test, for the Ambiguous answer' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Test-OERAmbiguousNameError { $true }
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('x'), 'ApproverUnresolved', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            # The owner's answer decides, even over an id that would otherwise be NotFound.
            Get-OERApproverErrorClass -Record $Record | Should -BeExactly 'Ambiguous'
            Should -Invoke Test-OERAmbiguousNameError -Times 1 -Exactly -ParameterFilter { $Record.FullyQualifiedErrorId -eq 'ApproverUnresolved' }
        }
    }
}

Describe 'Get-OERApproverErrorClass cohort: the single owner of the approver lookup classification (BL-52)' {
    # Static: the source files are parsed, nothing in them runs. A "test" of one of the two internal ids
    # is a string constant that names it standing as an operand of a comparison operator (-eq, -ne,
    # -like, -notlike, -match, -notmatch, -contains, -notcontains, -in, -notin, each in every letter-case
    # form), as an argument of a string comparison method (StartsWith, EndsWith, Contains, Equals,
    # Compare, CompareOrdinal, IndexOf), or as a switch clause. The producers construct the ids and are
    # allowed (R-6): Resolve-OERPrincipal creates PrincipalUnresolved, and Resolve-OERApproverInput and
    # Resolve-OERDeclaredApprover test it to wrap it as ApproverUnresolved. Not seen: an id held in a
    # variable first, or built at run time.
    BeforeAll {
        $script:SourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../source')).Path
        $script:OwnerFile = 'Private/Get-OERApproverErrorClass.ps1'
        $script:Allowed = @(
            $script:OwnerFile
            'Private/Resolve-OERPrincipal.ps1'
            'Private/Resolve-OERApproverInput.ps1'
            'Private/Resolve-OERDeclaredApprover.ps1'
        )
        $script:SixSites = @(
            'Public/Set-OERGroupPimPolicy.ps1'
            'Public/Set-OERDirectoryRoleManagementPolicy.ps1'
            'Public/Set-OERRoleManagementPolicy.ps1'
            'Private/Sync-OERStructureGroup.ps1'
            'Private/Sync-OERStructureDirectoryRoleManagementPolicy.ps1'
            'Private/Sync-OERStructureRoleManagementPolicy.ps1'
        )

        # Every test of an internal id in the parsed text, as 'line N: <text>'.
        function script:Get-ApproverIdTest {
            param([System.Management.Automation.Language.Ast]$Ast)
            $Comparison = @(
                'Ieq', 'Ceq', 'Ine', 'Cne', 'Ilike', 'Clike', 'Inotlike', 'Cnotlike', 'Imatch', 'Cmatch', 'Inotmatch', 'Cnotmatch',
                'Icontains', 'Ccontains', 'Inotcontains', 'Cnotcontains', 'Iin', 'Cin', 'Inotin', 'Cnotin'
            )
            $Methods = @('StartsWith', 'EndsWith', 'Contains', 'Equals', 'Compare', 'CompareOrdinal', 'IndexOf')
            $NamesId = {
                param($Node)
                ($Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                    $Node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
                [string]$Node.Value -match 'ApproverUnresolved|PrincipalUnresolved'
            }
            $HoldsId = {
                param($Node)
                $null -ne $Node -and @($Node.FindAll($NamesId, $true)).Count -gt 0
            }
            $Hits = $Ast.FindAll({
                    param($Node)
                    if ($Node -is [System.Management.Automation.Language.BinaryExpressionAst]) {
                        return ([string]$Node.Operator -in $Comparison) -and ((& $HoldsId $Node.Left) -or (& $HoldsId $Node.Right))
                    }
                    if ($Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                        $Member = $Node.Member
                        if ($Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $false }
                        if ([string]$Member.Value -notin $Methods) { return $false }
                        foreach ($Argument in @($Node.Arguments)) { if (& $HoldsId $Argument) { return $true } }
                        return $false
                    }
                    if ($Node -is [System.Management.Automation.Language.SwitchStatementAst]) {
                        foreach ($Clause in @($Node.Clauses)) { if (& $HoldsId $Clause.Item1) { return $true } }
                        return $false
                    }
                    $false
                }, $true)
            foreach ($Hit in $Hits) { 'line {0}: {1}' -f $Hit.Extent.StartLineNumber, ($Hit.Extent.Text -split "`n")[0].Trim() }
        }
        function script:Get-ApproverIdTestInText ([string]$Text) {
            $Tokens = $null
            $ParseErrors = $null
            Get-ApproverIdTest -Ast ([System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$ParseErrors))
        }
        function script:Get-ApproverIdTestInFile ([string]$Path) {
            $Tokens = $null
            $ParseErrors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors)
            @($ParseErrors).Count | Should -Be 0 -Because "the file '$Path' must parse"
            Get-ApproverIdTest -Ast $Ast
        }
    }

    It 'the scan is not inert: it finds the owner''s own tests and every inline shape, and no construction' {
        # The positive reach proof for the negative assertion below: the scan that must find nothing
        # elsewhere finds the two tests the owner is allowed to hold, and each inline shape a site
        # could carry.
        @(Get-ApproverIdTestInFile -Path (Join-Path $script:SourceRoot $script:OwnerFile)).Count | Should -Be 2
        foreach ($Shape in @(
                "if (([string]`$PSItem.FullyQualifiedErrorId).StartsWith('ApproverUnresolved', [System.StringComparison]::Ordinal)) { }"
                "if ([string]`$E.FullyQualifiedErrorId -like 'PrincipalUnresolved*') { }"
                "if (`$E.FullyQualifiedErrorId -match '^ApproverUnresolved') { }"
                "if (`$Id -eq 'ApproverUnresolved') { }"
                "if ('PrincipalUnresolved' -ceq `$Id) { }"
                "if (`$Id -notlike 'ApproverUnresolved*') { }"
                "if (`$Id -in @('ApproverUnresolved', 'PrincipalUnresolved')) { }"
                "if ([string]::Equals(`$Id, 'PrincipalUnresolved', [System.StringComparison]::Ordinal)) { }"
                "switch -Wildcard (`$Id) { 'ApproverUnresolved*' { } }"
            )) {
            @(Get-ApproverIdTestInText -Text $Shape).Count | Should -Be 1 -Because "the shape must be found: $Shape"
        }
        # A producer constructs the id: that is not a test, and an id named in a message is not one either.
        @(Get-ApproverIdTestInText -Text "throw [System.Management.Automation.ErrorRecord]::new(`$Ex, 'ApproverUnresolved', [System.Management.Automation.ErrorCategory]::ObjectNotFound, `$Value)").Count | Should -Be 0
        @(Get-ApproverIdTestInText -Text "Write-Verbose 'ApproverUnresolved is internal'").Count | Should -Be 0
    }

    It 'no file under source/ other than the classifier and the three producers tests ApproverUnresolved or PrincipalUnresolved' {
        $Files = @(Get-ChildItem -LiteralPath $script:SourceRoot -Recurse -File -Filter '*.ps1')
        # The scan reaches the tree: the six sites are among the files read.
        $Files.Count | Should -BeGreaterThan 100
        foreach ($Site in $script:SixSites) {
            @($Files | Where-Object { $_.FullName -eq (Get-Item -LiteralPath (Join-Path $script:SourceRoot $Site)).FullName }).Count | Should -Be 1
        }
        $Found = @(foreach ($File in $Files) {
                $Relative = $File.FullName.Substring($script:SourceRoot.Length + 1).Replace('\', '/')
                if ($Relative -in $script:Allowed) { continue }
                foreach ($Hit in (Get-ApproverIdTestInFile -Path $File.FullName)) { '{0}: {1}' -f $Relative, $Hit }
            })
        $Found | Should -BeNullOrEmpty -Because 'Get-OERApproverErrorClass is the single owner of the classification; ask it instead'
    }

    It '<_> asks Get-OERApproverErrorClass' -ForEach @(
        'Public/Set-OERGroupPimPolicy.ps1'
        'Public/Set-OERDirectoryRoleManagementPolicy.ps1'
        'Public/Set-OERRoleManagementPolicy.ps1'
        'Private/Sync-OERStructureGroup.ps1'
        'Private/Sync-OERStructureDirectoryRoleManagementPolicy.ps1'
        'Private/Sync-OERStructureRoleManagementPolicy.ps1'
    ) {
        $File = Join-Path $script:SourceRoot $_
        Test-Path -LiteralPath $File | Should -BeTrue
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$Tokens, [ref]$ParseErrors)
        @($ParseErrors).Count | Should -Be 0
        $Calls = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and
                    $Node.GetCommandName() -eq 'Get-OERApproverErrorClass'
                }, $true))
        $Calls.Count | Should -BeGreaterThan 0
    }
}
