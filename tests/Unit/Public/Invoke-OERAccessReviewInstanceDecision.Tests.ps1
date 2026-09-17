BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Invoke-OERAccessReviewInstanceDecision' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-id' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
    }

    It 'applies decisions by default (applyDecisions URI)' {
        Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/applyDecisions'
        }
    }

    It 'resets decisions with -Reset (resetDecisions URI)' {
        Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -Reset -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/resetDecisions'
        }
    }

    It 'honors -WhatIf and makes no Graph call' {
        Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'writes a non-terminating error when definition is not found' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { $null }
        Invoke-OERAccessReviewInstanceDecision -Definition 'ghost' -Instance 'i1' -ErrorVariable e -ErrorAction SilentlyContinue
        $e | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'accepts pipeline input via AccessReviewDefinitionId and InstanceId aliases for apply' {
        [pscustomobject]@{
            AccessReviewDefinitionId = 'Q3'
            InstanceId               = 'i1'
        } | Invoke-OERAccessReviewInstanceDecision -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/applyDecisions'
        }
    }

    It 'passes TenantId to Initialize-OERAuth' {
        Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -TenantId 'contoso.onmicrosoft.com' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -ParameterFilter {
            $TenantId -eq 'contoso.onmicrosoft.com'
        }
    }

    Context 'destructive guard' {
        It 'declares ConfirmImpact High' {
            $Attr = (Get-Command Invoke-OERAccessReviewInstanceDecision).ScriptBlock.Attributes |
                Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $Attr.ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::High)
        }

        It 'warns that reset discards decisions irreversibly, BEFORE the POST fires' {
            $Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -MockWith { $Order.Add('post') }
            Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -Reset -Confirm:$false `
                -WarningVariable Warn -WarningAction SilentlyContinue
            $Order -join ',' | Should -Be 'post'
            @($Warn | Where-Object { $_.Message -match 'irreversibl' }).Count | Should -Be 1
        }

        It 'warns that apply commits revocations, BEFORE the POST fires' {
            $Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -MockWith { $Order.Add('post') }
            Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -Confirm:$false `
                -WarningVariable Warn -WarningAction SilentlyContinue
            $Order -join ',' | Should -Be 'post'
            @($Warn | Where-Object { $_.Message -match 'appl' }).Count | Should -Be 1
        }

        It 'does not POST under -WhatIf (Reset)' {
            Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -Reset -WhatIf
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not warn under -WhatIf (the warning belongs inside the ShouldProcess block)' {
            Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -Reset -WhatIf `
                -WarningVariable Warn -WarningAction SilentlyContinue
            @($Warn).Count | Should -Be 0
        }
    }

    It 'surfaces a Graph failure as a non-terminating error and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Invoke-OERAccessReviewInstanceDecision' }).Count |
            Should -Be 1
    }

    It 'surfaces a definition-resolution failure and scrubs the record' {
        # Drives the resolver catch that no test in this tree had ever entered --
        # source/Public/Invoke-OERAccessReviewInstanceDecision.ps1:73. Until now
        # Resolve-OERAccessReviewDefinitionId was only ever mocked to a value or to $null,
        # never to throw. That catch SWALLOWS -- it scrubs, builds a fresh
        # exception and returns -- so the scrub proof has to be Mock + Should -Invoke; a
        # $global:Error reference-identity check would be inert here.
        # Should -Invoke Invoke-OERGraphRequest -Times 0 is what separates this from the
        # Graph-failure It above: the resolver fails before the transport is ever reached.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = Invoke-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessReviewDefinitionResolveFailed,Invoke-OERAccessReviewInstanceDecision' }).Count |
            Should -Be 1
    }
}
