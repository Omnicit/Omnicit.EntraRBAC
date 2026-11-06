BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Set-OERResourceGroup' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
    }

    It 'GETs then PUTs preserving location and replacing tags' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'GET' -or -not $Method } {
            [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-net'; name = 'rg-net'; location = 'westeurope'; tags = [PSCustomObject]@{ old = 'x' }; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } {
            [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-net'; name = 'rg-net'; location = 'westeurope'; tags = [PSCustomObject]@{ env = 'prod' }; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
        }
        $Result = Set-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Tag @{ env = 'prod' }
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ResourceGroup'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and $Body.location -eq 'westeurope' -and $Body.tags.env -eq 'prod'
        }
    }

    It 'errors ResourceGroupNotFound when the GET 404s' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            $Rec = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('not found'), 'ResourceGroupNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
            throw $Rec
        }
        # This is the only test that enters the GET catch at Set-OERResourceGroup.ps1:78-86, so it
        # is the only possible cover for that catch's mandatory Remove-OERErrorRecord line.
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Set-OERResourceGroup -Subscription 'Prod' -Name 'missing' -Tag @{ a = 'b' } -ErrorAction SilentlyContinue -ErrorVariable Err
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
        # $Err[0] is the MOCK's record, not the cmdlet's: PowerShell auto-records the thrown record
        # at roughly a dozen call boundaries before the catch runs (13 records here; the mock throws
        # the bare code 'ResourceGroupNotFound' itself, so a -BeLike on index 0 passed even with the
        # cmdlet's Write-CmdletError deleted). Match the cmdlet-QUALIFIED id instead.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ResourceGroupNotFound,Set-OERResourceGroup' }).Count |
            Should -Be 1
    }

    It 'does not PUT under -WhatIf' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-net'; name = 'rg-net'; location = 'westeurope'; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
        }
        Set-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Tag @{ env = 'prod' } -WhatIf
        # T4: the read (GET/no-Method) must happen; the write (PUT) must not
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
    }

    It 'declares ConfirmImpact Medium for parity with the ARM create/update cohort' {
        $Attr = (Get-Command Set-OERResourceGroup).ScriptBlock.Attributes |
            Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $Attr.ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::Medium)
    }

    Context 'a read without a location (BL-161a)' {
        BeforeAll {
            # The GET answer comes from a script-scope variable the mock reads; the PUT is recorded.
            function script:Set-RgGetAnswer { param($Answer) $script:RgGetAnswer = $Answer }
        }

        BeforeEach {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $script:RgGetAnswer }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } {
                [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-net'; name = 'rg-net'; location = 'westeurope'; tags = [PSCustomObject]@{}; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
            }
        }

        It 'refuses <Case> with ResourceGroupValueUnknown and sends no PUT' -ForEach @(
            @{ Case = 'a $null answer'; Answer = $null }
            @{ Case = 'an answer without location'; Answer = @{ name = 'rg'; tags = @{} } }
            @{ Case = 'a blank location'; Answer = @{ location = '  ' } }
        ) {
            $script:RgGetAnswer = $Answer
            $null = Set-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Tag @{ a = 'b' } -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ResourceGroupValueUnknown,Set-OERResourceGroup' }).Count | Should -Be 1
            $Own = $Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ResourceGroupValueUnknown,Set-OERResourceGroup' } | Select-Object -First 1
            $Own.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidData)
            $Own.TargetObject | Should -Be 'rg-net'
            $Own.Exception.Message | Should -BeExactly "Azure Resource Manager returned resource group 'rg-net' without its location, and an update must send the location it has, so nothing was sent. Read the resource group with Get-OERResourceGroup and try again."
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'refuses under -WhatIf too, since the refusal stands before ShouldProcess' {
            $script:RgGetAnswer = @{ name = 'rg'; tags = @{} }
            $null = Set-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Tag @{ a = 'b' } -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ResourceGroupValueUnknown,Set-OERResourceGroup' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'sends the PUT with the location it read when the location is present' {
            $script:RgGetAnswer = [PSCustomObject]@{ location = 'westeurope' }
            $null = Set-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Tag @{ a = 'b' } -ErrorAction Stop
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Body.location -eq 'westeurope'
            }
        }

        # The cmdlet in a runspace with no try above it, the way a script calls it: under
        # -ErrorAction Stop as the last statement the refusal stops the statement. The fakes live in the
        # runspace's copy of the module scope and are checked before the call; the PUT counter is a
        # file the fake appends to.
        It 'stops with ResourceGroupValueUnknown in a script with no try, and sends no PUT' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Text = @'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERScope -Value { '/subscriptions/sub-guid/resourceGroups/rg' }
    Set-Item -Path function:script:Invoke-OERArmRequest -Value {
        param([string]$Method = 'GET', [string]$Path, [hashtable]$Body)
        [System.IO.File]::AppendAllText('#LOG#', "$Method`n")
        if ($Method -eq 'GET') { return $null }
    }
    foreach ($Fn in 'Initialize-OERAuth', 'Resolve-OERScope', 'Invoke-OERArmRequest') {
        $Cmd = Get-Command $Fn
        if ($Cmd.ModuleName -ne 'Omnicit.EntraRBAC' -or $Cmd.CommandType -ne 'Function') { throw "stub $Fn does not resolve to the module-scope function" }
    }
}
[System.IO.File]::AppendAllText('#LOG#', "STUBS:ok`n")
Set-OERResourceGroup -Subscription s -Name rg -Tag @{} -ErrorAction Stop
'@
            $Ps = [powershell]::Create()
            try {
                $null = $Ps.AddScript($Text.Replace('#LOG#', $Log.Replace("'", "''")))
                $Thrown = $null
                try { $null = $Ps.Invoke() } catch { $Thrown = $PSItem }
                $Thrown | Should -Not -BeNullOrEmpty
                $Cause = $Thrown.Exception
                if ($Cause -is [System.Management.Automation.MethodInvocationException] -and $Cause.InnerException) { $Cause = $Cause.InnerException }
                $Cause.ErrorRecord.FullyQualifiedErrorId | Should -Be 'ResourceGroupValueUnknown,Set-OERResourceGroup'
                $Logged = @(Get-Content -LiteralPath $Log)
                $Logged | Should -Contain 'STUBS:ok'
                $Logged | Should -Contain 'GET'
                @($Logged | Where-Object { $_ -eq 'PUT' }).Count | Should -Be 0
            } finally {
                $Ps.Dispose()
            }
        }
    }
}
