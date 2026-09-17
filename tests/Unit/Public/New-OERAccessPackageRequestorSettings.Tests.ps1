BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'New-OERAccessPackageRequestorSettings' {
    It 'defaults to all-false admin-only settings' {
        $r = New-OERAccessPackageRequestorSettings
        $r.PSObject.TypeNames | Should -Contain 'Omnicit.EntraRBAC.RequestorSettings'
        $r.GraphRequestorSettings.enableTargetsToSelfAddAccess           | Should -BeFalse
        $r.GraphRequestorSettings.enableOnBehalfRequestorsToAddAccess    | Should -BeFalse
        $r.GraphRequestorSettings.allowCustomAssignmentSchedule          | Should -BeFalse
        $r.GraphRequestorSettings.enableTargetsToSelfUpdateAccess        | Should -BeFalse
        $r.GraphRequestorSettings.enableTargetsToSelfRemoveAccess        | Should -BeFalse
        $r.GraphRequestorSettings.enableOnBehalfRequestorsToUpdateAccess | Should -BeFalse
        $r.GraphRequestorSettings.enableOnBehalfRequestorsToRemoveAccess | Should -BeFalse
        @($r.GraphRequestorSettings.onBehalfRequestors).Count            | Should -Be 0
    }
    It 'sets self request' {
        (New-OERAccessPackageRequestorSettings -AllowSelfRequest).GraphRequestorSettings.enableTargetsToSelfAddAccess | Should -BeTrue
    }
    It 'sets manager request with a requestorManager onBehalfRequestor and level' {
        $r = New-OERAccessPackageRequestorSettings -AllowManagerRequest -ManagerLevel 2
        $r.GraphRequestorSettings.enableOnBehalfRequestorsToAddAccess | Should -BeTrue
        $obr = @($r.GraphRequestorSettings.onBehalfRequestors)[0]
        $obr.'@odata.type' | Should -Be '#microsoft.graph.requestorManager'
        $obr.managerLevel  | Should -Be 2
    }
    It 'sets custom schedule and self-extend' {
        $r = New-OERAccessPackageRequestorSettings -AllowCustomSchedule -AllowSelfExtend
        $r.GraphRequestorSettings.allowCustomAssignmentSchedule   | Should -BeTrue
        $r.GraphRequestorSettings.enableTargetsToSelfUpdateAccess | Should -BeTrue
    }
    It 'emits enableTargetsToSelfRemoveAccess from -AllowSelfRemove rather than a hard-coded false' {
        (New-OERAccessPackageRequestorSettings -AllowSelfRemove).GraphRequestorSettings.enableTargetsToSelfRemoveAccess | Should -Be $true
        (New-OERAccessPackageRequestorSettings -AllowSelfRequest).GraphRequestorSettings.enableTargetsToSelfRemoveAccess | Should -Be $false
    }
    It 'emits the two on-behalf flags the builder previously omitted entirely' {
        $r = New-OERAccessPackageRequestorSettings -AllowOnBehalfUpdate -AllowOnBehalfRemove
        $r.GraphRequestorSettings.enableOnBehalfRequestorsToUpdateAccess | Should -Be $true
        $r.GraphRequestorSettings.enableOnBehalfRequestorsToRemoveAccess | Should -Be $true
    }
    It 'exposes AllowSelfRemove, AllowOnBehalfUpdate and AllowOnBehalfRemove on the returned object' {
        $r = New-OERAccessPackageRequestorSettings -AllowSelfRemove -AllowOnBehalfUpdate -AllowOnBehalfRemove
        $r.AllowSelfRemove | Should -BeTrue
        $r.AllowOnBehalfUpdate | Should -BeTrue
        $r.AllowOnBehalfRemove | Should -BeTrue
    }
}
