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

Describe 'Test-OERConsoleInputRedirected (BL-195)' {
    BeforeAll {
        $script:PwshPath = (Get-Process -Id $PID).Path
    }

    It 'returns a [bool] equal to the .NET property read by the test itself' {
        $Expected = [System.Console]::IsInputRedirected
        $Answer = InModuleScope $script:moduleName { Test-OERConsoleInputRedirected }
        $Answer | Should -BeOfType [bool]
        $Answer | Should -BeExactly $Expected
    }

    It 'returns $true in a child pwsh whose standard input is piped' {
        $Command = "Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop; " +
            "'ANSWER:' + (& (Get-Module Omnicit.EntraRBAC) { Test-OERConsoleInputRedirected })"
        $Output = 'y' | & $script:PwshPath -NoProfile -Command $Command 2>&1
        @($Output | ForEach-Object { "$_" }) | Should -Contain 'ANSWER:True'
    }
}

Describe 'Test-OERConsoleInputRedirected is the single reader of the console input state (BL-195)' {
    BeforeAll {
        $script:SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../source')).Path
    }

    It 'is the only file under source that names IsInputRedirected' {
        $Named = @(Get-ChildItem -Path $script:SourceRoot -Recurse -File -Filter '*.ps1' |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'IsInputRedirected' } |
                ForEach-Object { $_.Name })
        $Named | Should -Be @('Test-OERConsoleInputRedirected.ps1')
    }

    It 'is called only by Test-OERHostCanConfirm' {
        $Callers = @(Get-ChildItem -Path $script:SourceRoot -Recurse -File -Filter '*.ps1' |
                Where-Object { $_.Name -ne 'Test-OERConsoleInputRedirected.ps1' -and
                    (Get-Content -LiteralPath $_.FullName -Raw) -match 'Test-OERConsoleInputRedirected' } |
                ForEach-Object { $_.Name })
        $Callers | Should -Be @('Test-OERHostCanConfirm.ps1')
    }
}
