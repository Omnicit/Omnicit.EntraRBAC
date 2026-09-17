BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERAccessReviewInstanceDecision' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-id' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'dec1'; decision = 'Approve'; principal = @{ displayName = 'Anna' } }) }
        }
    }

    It 'reads instance decisions' {
        $d = Get-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1'
        $d.Decision  | Should -Be 'Approve'
        $d.Principal | Should -Be 'Anna'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/decisions'
        }
    }

    It 'reads stage decisions when -Stage is given' {
        Get-OERAccessReviewInstanceDecision -Definition 'def-id' -Instance 'i1' -Stage 's1'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/stages/s1/decisions'
        }
    }

    It 'tags output as Omnicit.EntraRBAC.AccessReviewDecision' {
        $d = Get-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1'
        $d.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewDecision'
    }

    It 'writes a non-terminating error when definition not found' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { $null }
        Get-OERAccessReviewInstanceDecision -Definition 'ghost' -Instance 'i1' -ErrorVariable e -ErrorAction SilentlyContinue
        $e | Should -Not -BeNullOrEmpty
    }

    It 'accepts Instance from pipeline by property name via AccessReviewInstanceId alias' {
        [pscustomobject]@{ AccessReviewDefinitionId = 'def-id'; AccessReviewInstanceId = 'i2' } |
            Get-OERAccessReviewInstanceDecision
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -like '*/instances/i2/decisions'
        }
    }

    It 'accepts Instance from pipeline by property name via InstanceId alias' {
        [pscustomobject]@{ AccessReviewDefinitionId = 'def-id'; InstanceId = 'i3' } |
            Get-OERAccessReviewInstanceDecision
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -like '*/instances/i3/decisions'
        }
    }

    It 'passes TenantId to Initialize-OERAuth' {
        Get-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' -TenantId 'contoso.onmicrosoft.com'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -ParameterFilter {
            $TenantId -eq 'contoso.onmicrosoft.com'
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
        $Result = Get-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Get-OERAccessReviewInstanceDecision' }).Count |
            Should -Be 1
    }

    It 'surfaces a definition-resolution failure and scrubs the record' {
        # Drives the resolver catch that no test in this tree had ever entered --
        # source/Public/Get-OERAccessReviewInstanceDecision.ps1:61. Until now
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
        $Result = Get-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessReviewDefinitionResolveFailed,Get-OERAccessReviewInstanceDecision' }).Count |
            Should -Be 1
    }

    Context 'paging (-All opt-in, Task 7 closes PR36 deliberately-not-fixed item 3)' {
        It 'passes -All to the instance-level decisions read' {
            Get-OERAccessReviewInstanceDecision -Definition 'Q3' -Instance 'i1' | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/decisions' -and $All
            }
        }

        It 'passes -All to the stage-level decisions read when -Stage is given' {
            Get-OERAccessReviewInstanceDecision -Definition 'def-id' -Instance 'i1' -Stage 's1' | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/stages/s1/decisions' -and $All
            }
        }
    }
}
