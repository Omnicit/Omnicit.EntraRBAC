BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERAccessReviewChange' {
    BeforeEach {
        # Built in BeforeEach (not the Describe body) so it survives the Pester v5 discovery/run phase
        # boundary -- a bare Describe-scope variable is $null inside the It at run time.
        # Shape mirrors ConvertTo-OERAccessReviewDefinition: raw Graph reviewer scopes, a raw
        # settings.recurrence object, and the raw settings dictionary.
        $script:CurrentReview = [PSCustomObject]@{
            Id                      = 'ar-1'
            DisplayName             = 'Q3 AP review'
            DescriptionForAdmins    = 'admin text'
            DescriptionForReviewers = 'reviewer text'
            AccessPackageId         = 'ap-1'
            AssignmentPolicyId      = 'pol-1'
            Reviewers               = @(@{ query = '/users/usr-1' })
            FallbackReviewers       = @()
            DurationInDays          = 14
            Recurrence              = @{
                pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
            }
            Settings                = @{
                instanceDurationInDays          = 14
                mailNotificationsEnabled        = $true
                reminderNotificationsEnabled    = $false
                justificationRequiredOnApproval = $true
                recommendationsEnabled          = $false
                autoApplyDecisionsEnabled       = $false
                defaultDecision                 = 'None'
            }
        }
    }

    It 'reports no change when every declared field already matches' {
        $Declared = [PSCustomObject]@{
            displayName      = 'Q3 AP review'
            accessPackage    = 'ap-1'
            assignmentPolicy = 'pol-1'
            recurrence       = 'Quarterly'
            startDate        = '2026-07-01'
            durationInDays   = 14
            descriptionForAdmins = 'admin text'
            mailNotification = $true
            defaultDecision  = 'None'
        }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $false
            $Change.SetParams            | Should -BeOfType [hashtable]
            $Change.SetParams.Keys.Count | Should -Be 0
            @($Change.NotApplied) | Should -BeNullOrEmpty
        }
    }

    It 'sends only the drifted settings fields' {
        $Declared = [PSCustomObject]@{
            displayName = 'Q3 AP review'; durationInDays = 21; autoApplyDecisions = $true
        }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.Changed                     | Should -Be $true
            $Change.SetParams.DurationInDays     | Should -Be 21
            $Change.SetParams.AutoApplyDecisions | Should -Be $true
            $Change.SetParams.Keys               | Should -Not -Contain 'MailNotification'
            $Change.SetParams.Keys               | Should -Not -Contain 'DefaultDecision'
        }
    }

    It 'never touches a field the document does not declare' {
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.Changed              | Should -Be $false
            $Change.SetParams            | Should -BeOfType [hashtable]
            $Change.SetParams.Keys.Count | Should -Be 0
        }
    }

    It 'updates both descriptions independently' {
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; descriptionForReviewers = 'new' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).SetParams
            $P.DescriptionForReviewers | Should -Be 'new'
            $P.Keys                    | Should -Not -Contain 'DescriptionForAdmins'
        }
    }

    It 'reads a settings value from a PSCustomObject as well as from a Graph dictionary' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Settings = [PSCustomObject]@{ instanceDurationInDays = 14; defaultDecision = 'None' }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; durationInDays = 14; defaultDecision = 'None' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).Changed | Should -Be $false
        }
    }

    It 'sends a declared setting the live definition does not carry at all' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Settings = @{ instanceDurationInDays = 14 }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; requireJustification = $false }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.Changed                       | Should -Be $true
            $Change.SetParams.RequireJustification | Should -Be $false
        }
    }

    It 'reports no reviewer change when the resolved ids match the live queries' {
        $Reviewer = [PSCustomObject]@{
            Manager               = $false
            SelfReview            = $false
            Reviewer              = @('anna@contoso.com')
            ReviewerGroup         = @()
            FallbackReviewer      = @()
            FallbackReviewerGroup = @()
            ReviewerKey           = @('usr-1')
            FallbackKey           = @()
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer
            $Change.Changed | Should -Be $false
        }
    }

    It 'matches a live reviewer id case-insensitively' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Reviewers = @(@{ query = '/users/USR-1' })
        $Reviewer = [PSCustomObject]@{
            Manager               = $false
            SelfReview            = $false
            Reviewer              = @('anna@contoso.com')
            ReviewerGroup         = @()
            FallbackReviewer      = @()
            FallbackReviewerGroup = @()
            ReviewerKey           = @('usr-1')
            FallbackKey           = @()
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer).Changed |
                Should -Be $false
        }
    }

    It 'sends every reviewer parameter together when the reviewer set differs' {
        $Reviewer = [PSCustomObject]@{
            Manager               = $true
            SelfReview            = $false
            Reviewer              = @()
            ReviewerGroup         = @()
            FallbackReviewer      = @('anna@contoso.com')
            FallbackReviewerGroup = @('sec-fallback')
            ReviewerKey           = @('manager')
            FallbackKey           = @('usr-1', 'grp-1')
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer).SetParams
            $P.Manager                  | Should -Be $true
            @($P.FallbackReviewer)      | Should -Be @('anna@contoso.com')
            @($P.FallbackReviewerGroup) | Should -Be @('sec-fallback')
        }
    }

    It 'sends the whole reviewer unit when only the fallback list differs' {
        $Reviewer = [PSCustomObject]@{
            Manager               = $false
            SelfReview            = $false
            Reviewer              = @('anna@contoso.com')
            ReviewerGroup         = @()
            FallbackReviewer      = @('bo@contoso.com')
            FallbackReviewerGroup = @()
            ReviewerKey           = @('usr-1')
            FallbackKey           = @('usr-2')
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer).SetParams
            # The primary reviewer list is unchanged but must still be sent, because
            # Set-OERAccessReviewDefinition rebuilds BOTH arrays as soon as any reviewer param is bound.
            @($P.Reviewer)         | Should -Be @('anna@contoso.com')
            @($P.FallbackReviewer) | Should -Be @('bo@contoso.com')
        }
    }

    It 'seeds the undeclared fallback reviewers from the live definition so they are not wiped' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.FallbackReviewers = @(@{ query = '/groups/grp-9/transitiveMembers' }, @{ query = '/users/usr-9' })
        $Reviewer = [PSCustomObject]@{
            HasReviewers          = $true
            HasFallbackReviewers  = $false
            Manager               = $false
            SelfReview            = $false
            Reviewer              = @('bo@contoso.com')
            ReviewerGroup         = @()
            FallbackReviewer      = @()
            FallbackReviewerGroup = @()
            ReviewerKey           = @('usr-2')
            FallbackKey           = @()
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer).SetParams
            @($P.Reviewer)              | Should -Be @('bo@contoso.com')
            @($P.FallbackReviewerGroup) | Should -Be @('grp-9')
            @($P.FallbackReviewer)      | Should -Be @('usr-9')
        }
    }

    It 'seeds the undeclared primary reviewers from the live definition so they are not wiped' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Reviewers = @(@{ query = './manager' }, @{ query = '/users/usr-1' })
        $Reviewer = [PSCustomObject]@{
            HasReviewers          = $false
            HasFallbackReviewers  = $true
            Manager               = $false
            SelfReview            = $false
            Reviewer              = @()
            ReviewerGroup         = @()
            FallbackReviewer      = @('bo@contoso.com')
            FallbackReviewerGroup = @()
            ReviewerKey           = @()
            FallbackKey           = @('usr-2')
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer).SetParams
            $P.Manager             | Should -Be $true
            @($P.Reviewer)         | Should -Be @('usr-1')
            @($P.FallbackReviewer) | Should -Be @('bo@contoso.com')
            $P.Keys                | Should -Not -Contain 'SelfReview'
        }
    }

    It 'does not report a change when only the undeclared half differs' {
        # A document that declares reviewers but not fallbackReviewers must converge: the live
        # fallback list is not the document's business, so it can never keep forcing an update.
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.FallbackReviewers = @(@{ query = '/users/usr-9' })
        $Reviewer = [PSCustomObject]@{
            HasReviewers          = $true
            HasFallbackReviewers  = $false
            Manager               = $false
            SelfReview            = $false
            Reviewer              = @('anna@contoso.com')
            ReviewerGroup         = @()
            FallbackReviewer      = @()
            FallbackReviewerGroup = @()
            ReviewerKey           = @('usr-1')
            FallbackKey           = @()
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer).Changed |
                Should -Be $false
        }
    }

    It 'seeds an empty live reviewer list as a self review rather than an empty write' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Reviewers = @()
        $Reviewer = [PSCustomObject]@{
            HasReviewers          = $false
            HasFallbackReviewers  = $true
            Manager               = $false
            SelfReview            = $false
            Reviewer              = @()
            ReviewerGroup         = @()
            FallbackReviewer      = @('bo@contoso.com')
            FallbackReviewerGroup = @()
            ReviewerKey           = @()
            FallbackKey           = @('usr-2')
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer).SetParams
            $P.SelfReview | Should -Be $true
            $P.Keys       | Should -Not -Contain 'Reviewer'
        }
    }

    It 'treats an empty live reviewer list as self' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Reviewers = @()
        $Reviewer = [PSCustomObject]@{
            Manager               = $false
            SelfReview            = $true
            Reviewer              = @()
            ReviewerGroup         = @()
            FallbackReviewer      = @()
            FallbackReviewerGroup = @()
            ReviewerKey           = @('self')
            FallbackKey           = @()
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer).Changed |
                Should -Be $false
        }
    }

    It 'derives manager and group keys from the live reviewer queries' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Reviewers = @(@{ query = './manager' }, @{ query = '/groups/grp-1' })
        $Reviewer = [PSCustomObject]@{
            Manager               = $true
            SelfReview            = $false
            Reviewer              = @()
            ReviewerGroup         = @('IT-Reviewers')
            FallbackReviewer      = @()
            FallbackReviewerGroup = @()
            ReviewerKey           = @('manager', 'grp-1')
            FallbackKey           = @()
        }
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
            param($Declared, $Current, $Reviewer)
            (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer).Changed |
                Should -Be $false
        }
    }

    It 'sends recurrence and start date together when the cadence changes' {
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; recurrence = 'Monthly' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).SetParams
            $P.Recurrence | Should -Be 'Monthly'
            $P.StartDate  | Should -Be ([datetime]'2026-07-01')
            # The live range is noEnd, so there is nothing to carry forward.
            $P.Keys       | Should -Not -Contain 'EndDate'
            $P.Keys       | Should -Not -Contain 'Occurrences'
        }
    }

    It 'maps every live recurrence pattern back to its declared cadence' {
        $Current = $script:CurrentReview.PSObject.Copy()
        InModuleScope $script:moduleName -Parameters @{ Current = $Current } {
            param($Current)
            $Cases = @(
                @{ Type = 'weekly';          Interval = 1;  Cadence = 'Weekly' }
                @{ Type = 'absoluteMonthly'; Interval = 1;  Cadence = 'Monthly' }
                @{ Type = 'absoluteMonthly'; Interval = 3;  Cadence = 'Quarterly' }
                @{ Type = 'absoluteMonthly'; Interval = 12; Cadence = 'Annually' }
            )
            foreach ($Case in $Cases) {
                $Current.Recurrence = @{
                    pattern = @{ type = $Case.Type; interval = $Case.Interval }
                    range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                }
                $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; recurrence = $Case.Cadence }
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
                $Change.Changed | Should -Be $false -Because "$($Case.Type)/$($Case.Interval) is $($Case.Cadence)"
            }
            # A definition with no recurrence object at all is a OneTime review.
            $Current.Recurrence = $null
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; recurrence = 'OneTime' }
            (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).Changed | Should -Be $false
        }
    }

    It 'carries the declared occurrences into the recurrence unit' {
        $Declared = [PSCustomObject]@{
            displayName = 'Q3 AP review'; recurrence = 'Quarterly'; startDate = '2026-07-01'; occurrences = 4
        }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).SetParams
            $P.Recurrence  | Should -Be 'Quarterly'
            $P.StartDate   | Should -Be ([datetime]'2026-07-01')
            $P.Occurrences | Should -Be 4
        }
    }

    It 'carries the declared endDate into the recurrence unit' {
        $Declared = [PSCustomObject]@{
            displayName = 'Q3 AP review'; recurrence = 'Quarterly'; startDate = '2026-07-01'; endDate = '2027-07-01'
        }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).SetParams
            $P.Recurrence | Should -Be 'Quarterly'
            $P.EndDate    | Should -Be ([datetime]'2027-07-01')
            $P.Keys       | Should -Not -Contain 'Occurrences'
        }
    }

    It 'reports no change for a OneTime review that declares a startDate' {
        # A OneTime review carries no settings.recurrence at all, so there is no live range to compare
        # against. Without the OneTime gate the declared startDate would look like drift on EVERY run
        # and issue a PUT that changes nothing -- the apply engine would never settle.
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Recurrence = $null
        InModuleScope $script:moduleName -Parameters @{ Current = $Current } {
            param($Current)
            $Declared = [PSCustomObject]@{
                displayName = 'Q3 AP review'; recurrence = 'OneTime'; startDate = '2026-07-01'
            }
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.Changed              | Should -Be $false
            $Change.SetParams            | Should -BeOfType [hashtable]
            $Change.SetParams.Keys.Count | Should -Be 0
            @($Change.NotApplied)        | Should -BeNullOrEmpty
        }
    }

    It 'reports no change for a OneTime review that declares only a startDate' {
        # recurrence omitted: the effective cadence falls back to the live one, which is OneTime here.
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Recurrence = $null
        InModuleScope $script:moduleName -Parameters @{ Current = $Current } {
            param($Current)
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; startDate = '2026-07-01' }
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.Changed              | Should -Be $false
            $Change.SetParams            | Should -BeOfType [hashtable]
            $Change.SetParams.Keys.Count | Should -Be 0
        }
    }

    It 'still converts a recurring review to OneTime and writes no range' {
        InModuleScope $script:moduleName -Parameters @{ Current = $script:CurrentReview } {
            param($Current)
            $Declared = [PSCustomObject]@{
                displayName = 'Q3 AP review'; recurrence = 'OneTime'; startDate = '2026-07-01'
            }
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).SetParams
            $P.Recurrence | Should -Be 'OneTime'
            $P.StartDate  | Should -Be ([datetime]'2026-07-01')
            $P.Keys       | Should -Not -Contain 'EndDate'
            $P.Keys       | Should -Not -Contain 'Occurrences'
        }
    }

    It 'carries a live endDate range forward when the document changes only the cadence' {
        # Set-OERAccessReviewDefinition rebuilds the WHOLE recurrence object and defaults the range to
        # noEnd, so an undeclared range half must ride along or the live end date is destroyed.
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Recurrence = @{
            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
            range   = @{ type = 'endDate'; startDate = '2026-07-01'; endDate = '2027-01-01' }
        }
        InModuleScope $script:moduleName -Parameters @{ Current = $Current } {
            param($Current)
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; recurrence = 'Monthly' }
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).SetParams
            $P.Recurrence | Should -Be 'Monthly'
            $P.EndDate    | Should -Be ([datetime]'2027-01-01')
            $P.Keys       | Should -Not -Contain 'Occurrences'
        }
    }

    It 'carries a live numbered range forward when the document changes only the cadence' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Recurrence = @{
            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
            range   = @{ type = 'numbered'; startDate = '2026-07-01'; numberOfOccurrences = 6 }
        }
        InModuleScope $script:moduleName -Parameters @{ Current = $Current } {
            param($Current)
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; recurrence = 'Monthly' }
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).SetParams
            $P.Recurrence  | Should -Be 'Monthly'
            $P.Occurrences | Should -Be 6
            $P.Keys        | Should -Not -Contain 'EndDate'
        }
    }

    It 'lets a declared range override the live range' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Recurrence = @{
            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
            range   = @{ type = 'endDate'; startDate = '2026-07-01'; endDate = '2027-01-01' }
        }
        InModuleScope $script:moduleName -Parameters @{ Current = $Current } {
            param($Current)
            $Declared = [PSCustomObject]@{
                displayName = 'Q3 AP review'; recurrence = 'Monthly'; occurrences = 4
            }
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).SetParams
            $P.Occurrences | Should -Be 4
            $P.Keys        | Should -Not -Contain 'EndDate'
        }
    }

    It 'reports the recurrence change as not applied when no start date is available' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.Recurrence = $null
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; recurrence = 'Monthly' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.Changed                  | Should -Be $false
            @($Change.NotApplied) -join ' '  | Should -Match 'startDate'
        }
    }

    It 'does not rewrite an unrepresentable live interval when another field changes' {
        # Live absoluteMonthly interval 6 (semi-annual) is outside New-OERAccessReviewRecurrence's
        # vocabulary (1/3/12). Its collapsed cadence is 'Monthly' (the same default the inventory
        # projection uses), so the declared 'Monthly' does not even look like drift -- only the
        # startDate change forces the recurrence unit to be considered at all. Rebuilding the
        # recurrence from 'Monthly' here would silently downgrade the live semi-annual review.
        InModuleScope $script:moduleName {
            $Current = [PSCustomObject]@{
                DisplayName = 'R'
                Recurrence  = [PSCustomObject]@{
                    pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 6; dayOfMonth = 1 }
                    range   = [PSCustomObject]@{ type = 'noEnd'; startDate = '2026-01-01' }
                }
                Settings    = @{}
            }
            $Declared = [PSCustomObject]@{ displayName = 'R'; recurrence = 'Monthly'; startDate = '2026-02-01' }
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.SetParams.ContainsKey('Recurrence') | Should -Be $false
            $Change.SetParams.ContainsKey('StartDate')  | Should -Be $false
            ($Change.NotApplied -join ' ') | Should -Match 'interval 6'
        }
    }

    It 'still rewrites the recurrence when the live interval is representable' {
        InModuleScope $script:moduleName {
            $Current = [PSCustomObject]@{
                DisplayName = 'R'
                Recurrence  = [PSCustomObject]@{
                    pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                    range   = [PSCustomObject]@{ type = 'noEnd'; startDate = '2026-01-01' }
                }
                Settings    = @{}
            }
            $Declared = [PSCustomObject]@{ displayName = 'R'; recurrence = 'Monthly'; startDate = '2026-02-01' }
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.SetParams.Recurrence | Should -Be 'Monthly'
            $Change.SetParams.StartDate  | Should -Be ([datetime]'2026-02-01')
            @($Change.NotApplied)        | Should -BeNullOrEmpty
        }
    }

    It 'reports an unrepresentable weekly interval as not applied' {
        InModuleScope $script:moduleName {
            $Current = [PSCustomObject]@{
                DisplayName = 'R'
                Recurrence  = [PSCustomObject]@{
                    pattern = [PSCustomObject]@{ type = 'weekly'; interval = 2 }
                    range   = [PSCustomObject]@{ type = 'noEnd'; startDate = '2026-01-01' }
                }
                Settings    = @{}
            }
            $Declared = [PSCustomObject]@{ displayName = 'R'; recurrence = 'Weekly'; startDate = '2026-02-01' }
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.SetParams.ContainsKey('Recurrence') | Should -Be $false
            ($Change.NotApplied -join ' ') | Should -Match 'interval 2'
        }
    }

    It 'reports a scope change as not applied instead of updating it' {
        $Declared = [PSCustomObject]@{
            displayName      = 'Q3 AP review'
            accessPackage    = '99999999-9999-9999-9999-999999999999'
            assignmentPolicy = 'pol-1'
        }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $false
            @($Change.NotApplied) -join ' ' | Should -Match 'accessPackage'
            @($Change.NotApplied) -join ' ' | Should -Match 'immutable'
        }
    }

    It 'does not report a declared display-name scope as drift' {
        # The document carries display names while the live definition carries ids, so a non-GUID
        # scope value cannot be compared offline and must not produce a false NotApplied on every apply.
        $Declared = [PSCustomObject]@{
            displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
        }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.Changed                  | Should -Be $false
            @($Change.NotApplied)            | Should -BeNullOrEmpty
        }
    }

    It 'does not report a matching GUID scope as drift' {
        $Current = $script:CurrentReview.PSObject.Copy()
        $Current.AccessPackageId = '99999999-9999-9999-9999-999999999999'
        $Declared = [PSCustomObject]@{
            displayName = 'Q3 AP review'; accessPackage = '99999999-9999-9999-9999-999999999999'
        }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            @((Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).NotApplied) |
                Should -BeNullOrEmpty
        }
    }

    It 'never puts the definition id into the set parameters' {
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review'; durationInDays = 30 }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $P = (Resolve-OERAccessReviewChange -Declared $Declared -Current $Current).SetParams
            $P.Keys | Should -Not -Contain 'Id'
            $P.Keys | Should -Not -Contain 'DisplayName'
        }
    }

    It 'tags the result object' {
        $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
        InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
            param($Declared, $Current)
            $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
            $Change.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewChange'
        }
    }

    Context 'explicit JSON null' {
        It 'treats an explicit null mailNotification as undeclared and does not disable it' {
            $Declared = '{ "displayName": "Q3 AP review", "mailNotification": null }' | ConvertFrom-Json
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
                param($Declared, $Current)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
                $Change.Changed | Should -Be $false
                @($Change.SetParams.Keys) | Should -Not -Contain 'MailNotification'
            }
        }

        It 'treats an explicit null on every settings field as undeclared' {
            $Json = '{ "displayName": "Q3 AP review", "mailNotification": null, ' +
                    '"reminderNotification": null, "requireJustification": null, ' +
                    '"recommendationsEnabled": null, "autoApplyDecisions": null, ' +
                    '"durationInDays": null, "defaultDecision": null, ' +
                    '"descriptionForAdmins": null, "descriptionForReviewers": null }'
            $Declared = $Json | ConvertFrom-Json
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
                param($Declared, $Current)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
                $Change.Changed | Should -Be $false
                $Change.SetParams            | Should -BeOfType [hashtable]
                $Change.SetParams.Keys.Count | Should -Be 0
            }
        }

        It 'treats an explicit null recurrence as undeclared and leaves the live cadence alone' {
            $Declared = '{ "displayName": "Q3 AP review", "recurrence": null, "startDate": null }' | ConvertFrom-Json
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $script:CurrentReview } {
                param($Declared, $Current)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current
                $Change.Changed | Should -Be $false
                @($Change.SetParams.Keys) | Should -Not -Contain 'Recurrence'
            }
        }
    }

    Context 'live reviewer scopes carrying the API version prefix Graph adds on read' {
        # Microsoft Graph NORMALIZES a reviewer scope query: this module writes '/users/{id}' with no
        # prefix, and a GET reads it back as '/v1.0/users/{id}'. The anchored '^/users/' parse this
        # diff used to carry matched none of those, the live key list came out EMPTY, and the code
        # then concluded the review was a SELF review. On the write path that replaces real named
        # reviewers with the requestor, which is live-state corruption rather than an export cosmetic.
        # The user id below is the live string from the tenant that exposed the defect.
        BeforeEach {
            $script:PrefixedUser = '/v1.0/users/00000000-0000-0000-0000-000000000049'
            $script:PrefixedUserId = '00000000-0000-0000-0000-000000000049'
        }

        It 'reads a /v1.0/users/{id} scope as that user and reports no drift against the same id' {
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
            $Reviewer = [PSCustomObject]@{
                HasReviewers = $true; HasFallbackReviewers = $false
                Manager = $false; SelfReview = $false
                Reviewer = @('00000000-0000-0000-0000-000000000049'); ReviewerGroup = @()
                FallbackReviewer = @(); FallbackReviewerGroup = @()
                ReviewerKey = @('00000000-0000-0000-0000-000000000049'); FallbackKey = @()
            }
            $Current = $script:CurrentReview
            $Current.Reviewers = @(@{ query = $script:PrefixedUser })
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
                param($Declared, $Current, $Reviewer)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer
                $Change.Changed | Should -Be $false
                @($Change.SetParams.Keys) | Should -Not -Contain 'SelfReview'
                @($Change.SetParams.Keys) | Should -Not -Contain 'Reviewer'
            }
        }

        It 'never calls a prefixed live scope a self review when the document leaves reviewers undeclared' {
            # THE corruption case. The primary half is undeclared, so it is seeded from live and
            # re-sent verbatim. Reading the prefixed scope as "no reviewers" seeded SelfReview = $true
            # and wiped the real reviewer.
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
            $Reviewer = [PSCustomObject]@{
                HasReviewers = $false; HasFallbackReviewers = $true
                Manager = $false; SelfReview = $false
                Reviewer = @(); ReviewerGroup = @()
                FallbackReviewer = @('fb-9'); FallbackReviewerGroup = @()
                ReviewerKey = @(); FallbackKey = @('fb-9')
            }
            $Current = $script:CurrentReview
            $Current.Reviewers = @(@{ query = $script:PrefixedUser })
            $Current.FallbackReviewers = @()
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer; UserId = $script:PrefixedUserId } {
                param($Declared, $Current, $Reviewer, $UserId)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer
                $Change.Changed | Should -Be $true
                @($Change.SetParams.Keys) | Should -Not -Contain 'SelfReview'
                @($Change.SetParams.Reviewer) | Should -Contain $UserId
                @($Change.SetParams.FallbackReviewer) | Should -Contain 'fb-9'
            }
        }

        It 'reads prefixed group and fallback scopes as their object ids' {
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
            $Reviewer = [PSCustomObject]@{
                HasReviewers = $true; HasFallbackReviewers = $true
                Manager = $false; SelfReview = $false
                Reviewer = @(); ReviewerGroup = @('grp-1')
                FallbackReviewer = @('fb-9'); FallbackReviewerGroup = @()
                ReviewerKey = @('grp-1'); FallbackKey = @('fb-9')
            }
            $Current = $script:CurrentReview
            $Current.Reviewers = @(@{ query = '/beta/groups/grp-1/transitiveMembers' })
            $Current.FallbackReviewers = @(@{ query = '/v1.0/users/fb-9' })
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
                param($Declared, $Current, $Reviewer)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer
                $Change.Changed | Should -Be $false
            }
        }
    }

    Context 'an unparsed live reviewer scope is not an absent one' {
        It 'keeps a genuinely empty live reviewer collection as the self-review shape' {
            # Counterpart guard: distinguishing unparsed from empty must not stop an ACTUALLY empty
            # live collection from seeding SelfReview into the undeclared half.
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
            $Reviewer = [PSCustomObject]@{
                HasReviewers = $false; HasFallbackReviewers = $true
                Manager = $false; SelfReview = $false
                Reviewer = @(); ReviewerGroup = @()
                FallbackReviewer = @('fb-9'); FallbackReviewerGroup = @()
                ReviewerKey = @(); FallbackKey = @('fb-9')
            }
            $Current = $script:CurrentReview
            $Current.Reviewers = @()
            $Current.FallbackReviewers = @()
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
                param($Declared, $Current, $Reviewer)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer
                $Change.Changed | Should -Be $true
                $Change.SetParams.SelfReview | Should -Be $true
            }
        }

        It 'refuses the reviewer unit rather than seeding an undeclared half that carries an unparsed scope' {
            # './owners' is a documented scope this module cannot re-send. The primary half is
            # undeclared, so it would be seeded verbatim -- but only the PARSED subset can be seeded,
            # which silently deletes the reviewer. Suppress the unit and report it instead.
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
            $Reviewer = [PSCustomObject]@{
                HasReviewers = $false; HasFallbackReviewers = $true
                Manager = $false; SelfReview = $false
                Reviewer = @(); ReviewerGroup = @()
                FallbackReviewer = @('fb-9'); FallbackReviewerGroup = @()
                ReviewerKey = @(); FallbackKey = @('fb-9')
            }
            $Current = $script:CurrentReview
            $Current.Reviewers = @(@{ query = './owners' })
            $Current.FallbackReviewers = @()
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
                param($Declared, $Current, $Reviewer)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer
                @($Change.SetParams.Keys) | Should -Not -Contain 'SelfReview'
                @($Change.SetParams.Keys) | Should -Not -Contain 'Reviewer'
                @($Change.SetParams.Keys) | Should -Not -Contain 'FallbackReviewer'
                @($Change.NotApplied) | Should -Not -BeNullOrEmpty
                (@($Change.NotApplied) -join ' ') | Should -Match '\./owners'
                (@($Change.NotApplied) -join ' ') | Should -Match 'cannot express'
            }
        }

        It 'forces the change and names the replaced scope when the DECLARED half carries an unparsed live scope' {
            # The parsed keys match the declared set exactly, so a key-set comparison alone would
            # report convergence -- while a real extra reviewer sits live and unexpressed. Equality
            # cannot be proven, so the write goes out and the replaced query is named.
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
            $Reviewer = [PSCustomObject]@{
                HasReviewers = $true; HasFallbackReviewers = $false
                Manager = $false; SelfReview = $false
                Reviewer = @('usr-1'); ReviewerGroup = @()
                FallbackReviewer = @(); FallbackReviewerGroup = @()
                ReviewerKey = @('usr-1'); FallbackKey = @()
            }
            $Current = $script:CurrentReview
            $Current.Reviewers = @(@{ query = '/v1.0/users/usr-1' }, @{ query = './owners' })
            $Current.FallbackReviewers = @()
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
                param($Declared, $Current, $Reviewer)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer
                $Change.Changed | Should -Be $true
                @($Change.SetParams.Reviewer) | Should -Contain 'usr-1'
                (@($Change.Changes) -join ' ') | Should -Match '\./owners'
                (@($Change.Changes) -join ' ') | Should -Match 'replacing 1 live reviewer scope'
            }
        }

        It 'converges: the same diff run against the normalized post-write definition reports Unchanged' {
            # Symmetry guard. Forcing the change above must not make every apply report drift forever
            # -- after the PUT the definition carries only module-emitted forms (prefixed on read),
            # all of which parse, so the verification diff sees no unparsed scope.
            $Declared = [PSCustomObject]@{ displayName = 'Q3 AP review' }
            $Reviewer = [PSCustomObject]@{
                HasReviewers = $true; HasFallbackReviewers = $false
                Manager = $false; SelfReview = $false
                Reviewer = @('usr-1'); ReviewerGroup = @()
                FallbackReviewer = @(); FallbackReviewerGroup = @()
                ReviewerKey = @('usr-1'); FallbackKey = @()
            }
            $Current = $script:CurrentReview
            $Current.Reviewers = @(@{ query = '/v1.0/users/usr-1' })
            $Current.FallbackReviewers = @()
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Current = $Current; Reviewer = $Reviewer } {
                param($Declared, $Current, $Reviewer)
                $Change = Resolve-OERAccessReviewChange -Declared $Declared -Current $Current -DeclaredReviewer $Reviewer
                $Change.Changed | Should -Be $false
                @($Change.NotApplied) | Should -BeNullOrEmpty
            }
        }
    }
}
