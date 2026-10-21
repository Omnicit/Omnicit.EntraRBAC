BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Test-OERHostNonInteractive (BL-100)' {
    BeforeAll {
        . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
        $script:PwshPath = (Get-Process -Id $PID).Path

        # Starts a child pwsh that only imports the built module by name and asks the helper in module
        # scope. Nothing else runs in the child: no sign-in, no token request, no Graph call.
        function script:Invoke-ChildHostQuestion {
            param([string[]]$HostArgument)
            $Command = "Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop; " +
                "'ANSWER:' + (& (Get-Module Omnicit.EntraRBAC) { Test-OERHostNonInteractive })"
            $Output = & $script:PwshPath -NoProfile @HostArgument -Command $Command 2>&1
            [PSCustomObject]@{
                ExitCode = $LASTEXITCODE
                Output   = @($Output | ForEach-Object { "$_" })
            }
        }
    }

    It 'returns $true in a console host started with -NonInteractive' {
        $Run = Invoke-ChildHostQuestion -HostArgument '-NonInteractive'
        $Run.ExitCode | Should -Be 0
        $Run.Output | Should -Contain 'ANSWER:True'
    }

    It 'returns $true when the switch is spelled -noni, the shortest form' {
        $Run = Invoke-ChildHostQuestion -HostArgument '-noni'
        $Run.ExitCode | Should -Be 0
        $Run.Output | Should -Contain 'ANSWER:True'
    }

    It 'returns $false in a console host started without -NonInteractive' {
        $Run = Invoke-ChildHostQuestion -HostArgument @()
        $Run.ExitCode | Should -Be 0
        $Run.Output | Should -Contain 'ANSWER:False'
    }

    It 'returns $false in a runspace made with no PSHost (the Default Host)' {
        $Runspace = [runspacefactory]::CreateRunspace()
        $Runspace.Open()
        $Shell = [powershell]::Create()
        try {
            Install-OERTransportTripwireInRunspace -Runspace $Runspace
            $Shell.Runspace = $Runspace
            $null = $Shell.AddScript({
                    Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
                    "HOST:$($Host.Name)"
                    "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostNonInteractive })"
                }.ToString())
            $Output = @($Shell.Invoke())
            Test-OERTransportTripwireInRunspace -Runspace $Runspace
            $Output | Should -Be @('HOST:Default Host', 'ANSWER:False')
            $Shell.Streams.Error | Should -BeNullOrEmpty
        } finally {
            $Shell.Dispose()
            $Runspace.Dispose()
        }
    }

    It 'returns $false in a host that is not the console host (the answering host)' {
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "HOST:$($Host.Name)"
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostNonInteractive })"
        }
        $Run.Output | Should -Be @('HOST:OERAnsweringHost', 'ANSWER:False')
        $Run.Errors | Should -BeNullOrEmpty
    }

    It 'returns a [bool] and writes no error record' {
        $Result = InModuleScope $script:moduleName {
            $Before = $global:Error.Count
            $Answer = Test-OERHostNonInteractive -ErrorAction SilentlyContinue
            [PSCustomObject]@{ IsBool = ($Answer -is [bool]); NewErrors = $global:Error.Count - $Before }
        }
        $Result.IsBool | Should -BeTrue
        $Result.NewErrors | Should -Be 0
    }
}

Describe 'Test-OERHostNonInteractive is the single owner of the host question (BL-100)' {
    It 'is the only file under source that names _throwOnReadAndPrompt' {
        $SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../source')).Path
        $Named = @(Get-ChildItem -Path $SourceRoot -Recurse -File -Filter '*.ps1' |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '_throwOnReadAndPrompt' } |
                ForEach-Object { $_.Name })
        $Named | Should -Be @('Test-OERHostNonInteractive.ps1')
    }

    It 'is called in Initialize-OERAuth and by no other file under source' {
        $SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../source')).Path
        $Callers = @(Get-ChildItem -Path $SourceRoot -Recurse -File -Filter '*.ps1' |
                Where-Object { $_.Name -ne 'Test-OERHostNonInteractive.ps1' -and
                    (Get-Content -LiteralPath $_.FullName -Raw) -match 'Test-OERHostNonInteractive' } |
                ForEach-Object { $_.Name })
        $Callers | Should -Be @('Initialize-OERAuth.ps1')
    }
}
