# tests/Get-ProcessReport.Tests.ps1

Describe "Get-ProcessReport.ps1" -Tags 'ProcessReport' {

    # These will be populated by BeforeAll
    $SharedData = @{
        ScriptPathToTest = $null
        TempDir          = $null
    }

    BeforeAll {
        $RelativePathToScript = "..\Get-ProcessReport.ps1"
        $ScriptFile = $null
        try {
            # Resolve path relative to THIS test script's location ($PSScriptRoot here SHOULD be reliable for BeforeAll)
            $ScriptFile = (Resolve-Path (Join-Path $PSScriptRoot $RelativePathToScript) -ErrorAction Stop).Path
        }
        catch {
            Write-Error "FATAL in BeforeAll: Could not resolve script path. PSScriptRoot: '$PSScriptRoot', Relative: '$RelativePathToScript'. Error: $($_.Exception.Message)"
            throw # Re-throw to stop Pester
        }

        if (-not (Test-Path $ScriptFile -PathType Leaf)) {
            Write-Error "FATAL in BeforeAll: Resolved script path '$ScriptFile' does not exist or is not a file."
            throw # Re-throw to stop Pester
        }

        $SharedData.ScriptPathToTest = $ScriptFile
        Write-Host "BeforeAll: Set SharedData.ScriptPathToTest to '$($SharedData.ScriptPathToTest)'"

        $SharedData.TempDir = Join-Path $env:TEMP "ProcessReporterTests_$(Get-Random)"
        if (-not (Test-Path $SharedData.TempDir)) {
            New-Item -ItemType Directory -Path $SharedData.TempDir -Force | Out-Null
        }
        Write-Host "BeforeAll: Set SharedData.TempDir to '$($SharedData.TempDir)'"
    }

    AfterAll {
        if ($SharedData.TempDir -and (Test-Path $SharedData.TempDir)) {
            Write-Host "AfterAll: Removing TempDir '$($SharedData.TempDir)'"
            Remove-Item $SharedData.TempDir -Recurse -Force
        }
    }

    Context "Core Functionality with Mocks" {
        $mockProcesses = $null # etc.

        BeforeEach {
            # Access paths from $SharedData
            $CurrentScriptPath = $SharedData.ScriptPathToTest
            # $CurrentTempDir = $SharedData.TempDir # If needed by BeforeEach logic

            if (-not ($CurrentScriptPath -and (Test-Path $CurrentScriptPath -PathType Leaf))) {
                throw "FATAL in BeforeEach (Core): ScriptPathToTest from SharedData is invalid: '$CurrentScriptPath'"
            }

            # Mock data setup...
            $mockProcesses = @(
                [PSCustomObject]@{ Id = 1001; ProcessName = 'powershell'; UserName = 'TESTDOMAIN\User1'; WorkingSet64 = 200MB; CPU = 120 },
                [PSCustomObject]@{ Id = 1002; ProcessName = 'chrome'; UserName = 'TESTDOMAIN\User1'; WorkingSet64 = 500MB; CPU = 300 },
                [PSCustomObject]@{ Id = 1003; ProcessName = 'svchost'; UserName = 'NT AUTHORITY\SYSTEM'; WorkingSet64 = 50MB; CPU = 60 },
                [PSCustomObject]@{ Id = 1004; ProcessName = 'explorer'; UserName = 'TESTDOMAIN\User1'; WorkingSet64 = 150MB; CPU = 90 },
                [PSCustomObject]@{ Id = 1005; ProcessName = 'System'; UserName = $null; WorkingSet64 = 10MB; CPU = 10 }
            )
            $mockSystemWmiPerfObject = [PSCustomObject]@{ IDProcess = 1005; Name = 'System'; PercentProcessorTime = 1 }
            $mockWmiPerfData = @(
                [PSCustomObject]@{ IDProcess = 1001; PercentProcessorTime = 10; Name = 'powershell' },
                [PSCustomObject]@{ IDProcess = 1002; PercentProcessorTime = 25; Name = 'chrome' },
                [PSCustomObject]@{ IDProcess = 1003; PercentProcessorTime = 5; Name = 'svchost' },
                $mockSystemWmiPerfObject
            )
            $mockSystemWmiProcessForOwnerObject = [PSCustomObject]@{ ProcessId = 1005; Name = 'System' }
            Add-Member -InputObject $mockSystemWmiProcessForOwnerObject -MemberType ScriptMethod -Name GetOwner -Value {
                param(); return [PSCustomObject]@{ User = 'SYSTEM_WMI_Fallback'; Domain = 'NT AUTHORITY' }
            } -Force
            $mockWmiProcessDataForOwnerFallback = @( $mockSystemWmiProcessForOwnerObject )

            Mock Get-Process { param($IncludeUserName) return $mockProcesses } -ModuleName $CurrentScriptPath -Verifiable
            Mock Get-WmiObject -ModuleName $CurrentScriptPath -MockWith {
                param($Class, $Query)
                if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') { return $mockWmiPerfData }
                if ($Query -match "Win32_Process WHERE ProcessId = 1005") { return $mockWmiProcessDataForOwnerFallback | Where-Object {$_.ProcessId -eq 1005} }
                if ($Query -match "Win32_Process WHERE ProcessId") { return @() }
                return @()
            } -Verifiable
        }

        It "Generates CSV output to console by default" {
            $PathToRun = $SharedData.ScriptPathToTest
            Write-Host "DEBUG CSV Test: PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) { throw "Script not found in CSV Test! Path: '$PathToRun'" }
            
            $output = & $PathToRun -ErrorAction Stop
            $csvOutput = $output | ConvertFrom-Csv
            $csvOutput.Count | Should -Be ($mockProcesses.Count)
        }

        It "Generates JSON output to console when -Format json is specified" {
            $PathToRun = $SharedData.ScriptPathToTest
            Write-Host "DEBUG JSON Test: PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) { throw "Script not found in JSON Test! Path: '$PathToRun'" }

            $output = & $PathToRun -Format json -ErrorAction Stop
            # ...
        }
        # ... Add similar Write-Host and 'if' checks to ALL It blocks that use & $PathToRun ...
        It "Saves CSV report to specified -OutputPath" {
            $PathToRun = $SharedData.ScriptPathToTest
            $CurrentTempDir = $SharedData.TempDir
            Write-Host "DEBUG Save CSV Test: PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) { throw "Script not found in Save CSV Test! Path: '$PathToRun'" }

            $testCsvPath = Join-Path $CurrentTempDir "test_processes.csv"
            & $PathToRun -OutputPath $testCsvPath -ErrorAction Stop
            Test-Path $testCsvPath | Should -Be $true
        }
    }

    Context "Error Handling and Edge Cases" {
        BeforeEach { # Add a BeforeEach to this context as well if it doesn't inherit the parent's mocks as expected
            $CurrentScriptPath = $SharedData.ScriptPathToTest
            if (-not ($CurrentScriptPath -and (Test-Path $CurrentScriptPath -PathType Leaf))) {
                throw "FATAL in BeforeEach (Error Handling): ScriptPathToTest from SharedData is invalid: '$CurrentScriptPath'"
            }
            # If this context needs its own mocks, define them here using $CurrentScriptPath for -ModuleName
        }

        It "Handles empty process list from Get-Process gracefully (warns and exits)" {
            $PathToRun = $SharedData.ScriptPathToTest
            Write-Host "DEBUG (Empty List Test): PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) {
                throw "FATAL (Empty List Test): Script to test is invalid or not found: '$PathToRun'"
            }

            Mock Get-Process { @() } -ModuleName $PathToRun -Verifiable # Use $PathToRun for ModuleName
            Mock Get-WmiObject { @() } -ModuleName $PathToRun -Verifiable # Use $PathToRun for ModuleName
            
            $WarningResult = $null
            $ScriptBlock = {
                $WarningPreference = 'Continue'
                & $PathToRun -ErrorAction SilentlyContinue 
            }
            Invoke-Command -ScriptBlock $ScriptBlock -WarningVariable WarningResult -ErrorVariable ErrorResult -ErrorAction SilentlyContinue
            $WarningResult.Message | Should -Match "No process information could be gathered"
        }
        # ... Add similar Write-Host and 'if' checks to ALL It blocks in this context ...
    }
}
