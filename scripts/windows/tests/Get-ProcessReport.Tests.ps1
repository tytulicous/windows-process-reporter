# windows/tests/Get-ProcessReport.Tests.ps1

Describe "Get-ProcessReport.ps1 (Windows)" -Tags 'ProcessReport', 'Windows' {

    # $script:SharedData will be created and populated by BeforeAll
    $script:SharedData = $null # Initialize to null, BeforeAll will create the hashtable

    BeforeAll {
        # Initialize $script:SharedData as a new hashtable INSIDE BeforeAll
        $script:SharedData = @{
            ScriptPathToTest = $null
            TempDir          = $null
        }

        # Path to the Windows script
        $RelativePathToScript = "..\Get-ProcessReport.ps1" # Relative to this test script
        $ScriptFile = $null
        try {
            $ScriptFile = (Resolve-Path (Join-Path $PSScriptRoot $RelativePathToScript) -ErrorAction Stop).Path
        }
        catch {
            Write-Error "FATAL in BeforeAll (Windows): Could not resolve script path. PSScriptRoot: '$PSScriptRoot', Relative: '$RelativePathToScript'. Error: $($_.Exception.Message)"
            throw
        }

        if (-not (Test-Path $ScriptFile -PathType Leaf)) {
            Write-Error "FATAL in BeforeAll (Windows): Resolved script path '$ScriptFile' does not exist or is not a file."
            throw
        }

        $script:SharedData.ScriptPathToTest = $ScriptFile
        Write-Host "BeforeAll (Windows): Set script:SharedData.ScriptPathToTest to '$($script:SharedData.ScriptPathToTest)'"

        $script:SharedData.TempDir = Join-Path $env:TEMP "WinProcessReporterTests_$(Get-Random)"
        if (-not (Test-Path $script:SharedData.TempDir -PathType Container)) { # Use Container for directory
            New-Item -ItemType Directory -Path $script:SharedData.TempDir -Force -ErrorAction Stop | Out-Null
        }
        Write-Host "BeforeAll (Windows): Ensured script:SharedData.TempDir exists at '$($script:SharedData.TempDir)'"
    }

    AfterAll {
        if ($script:SharedData -and $script:SharedData.TempDir -and (Test-Path $script:SharedData.TempDir -PathType Container)) { # Use Container
            Write-Host "AfterAll (Windows): Removing TempDir '$($script:SharedData.TempDir)'"
            Remove-Item $script:SharedData.TempDir -Recurse -Force
        }
    }

    Context "Core Functionality with Mocks (Windows)" {
        $mockProcesses = $null
        $mockWmiPerfData = $null
        $mockWmiProcessDataForOwnerFallback = $null

        BeforeEach {
            $CurrentScriptPath = $script:SharedData.ScriptPathToTest

            if (-not ($CurrentScriptPath -and (Test-Path $CurrentScriptPath -PathType Leaf))) {
                throw "FATAL in BeforeEach (Windows Core): ScriptPathToTest from script:SharedData is invalid: '$CurrentScriptPath'"
            }

            # Define base mock data for each test run (Windows specific data if needed)
            $mockProcesses = @(
                [PSCustomObject]@{ Id = 1001; ProcessName = 'powershell'; UserName = 'TESTDOMAIN\User1'; WorkingSet64 = 200MB; CPU = 120 },
                [PSCustomObject]@{ Id = 1002; ProcessName = 'chrome'; UserName = 'TESTDOMAIN\User1'; WorkingSet64 = 500MB; CPU = 300 },
                [PSCustomObject]@{ Id = 1003; ProcessName = 'svchost'; UserName = 'NT AUTHORITY\SYSTEM'; WorkingSet64 = 50MB; CPU = 60 },
                [PSCustomObject]@{ Id = 1004; ProcessName = 'explorer'; UserName = 'TESTDOMAIN\User1'; WorkingSet64 = 150MB; CPU = 90 },
                [PSCustomObject]@{ Id = 1005; ProcessName = 'System'; UserName = $null; WorkingSet64 = 10MB; CPU = 10 } # For WMI owner fallback
            )

            $mockWmiPerfData = @(
                [PSCustomObject]@{ IDProcess = 1001; PercentProcessorTime = 10; Name = 'powershell' },
                [PSCustomObject]@{ IDProcess = 1002; PercentProcessorTime = 25; Name = 'chrome' },
                [PSCustomObject]@{ IDProcess = 1003; PercentProcessorTime = 5; Name = 'svchost' },
                [PSCustomObject]@{ IDProcess = 1005; Name = 'System'; PercentProcessorTime = 1 } # For PID 1005
                # PID 1004 (explorer) deliberately missing from WMI Perf Data to test default CPU 0
            )

            $mockSystemWmiProcessForOwnerObject = [PSCustomObject]@{ ProcessId = 1005; Name = 'System' }
            Add-Member -InputObject $mockSystemWmiProcessForOwnerObject -MemberType ScriptMethod -Name GetOwner -Value {
                param(); return [PSCustomObject]@{ User = 'SYSTEM_WMI_Fallback'; Domain = 'NT AUTHORITY' }
            } -Force
            $mockWmiProcessDataForOwnerFallback = @( $mockSystemWmiProcessForOwnerObject )

            # Mocks WITHOUT -ModuleName for testing a script file
            Mock Get-Process { param($IncludeUserName) return $mockProcesses } -Verifiable
            Mock Get-WmiObject -MockWith {
                param($Class, $Query)
                if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') { return $mockWmiPerfData }
                if ($Query -match "Win32_Process WHERE ProcessId = 1005") { return $mockWmiProcessDataForOwnerFallback | Where-Object {$_.ProcessId -eq 1005} }
                if ($Query -match "Win32_Process WHERE ProcessId") { return @() } # General catch for other PIDs if script tries
                return @() # Default empty for other WMI calls
            } -Verifiable
        }

        It "Generates CSV output to console by default (Windows)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            Write-Host "DEBUG CSV Test (Windows): PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) { throw "Script not found in CSV Test! Path: '$PathToRun'" }
            
            $output = & $PathToRun -ErrorAction Stop
            $csvOutput = $output | ConvertFrom-Csv

            $csvOutput.Count | Should -Be ($mockProcesses.Count)
            $csvOutput[0].PID | Should -Be '1002' # chrome (highest CPU in mock data after sorting)
            ($csvOutput | Where-Object PID -eq '1005').User | Should -Be 'NT AUTHORITY\SYSTEM_WMI_Fallback'
            ($csvOutput | Where-Object PID -eq '1004').CPU_Percent | Should -Be '0' # explorer, no WMI CPU data
        }

        It "Saves CSV report to specified -OutputPath (Windows)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $CurrentTempDir = $script:SharedData.TempDir

            Write-Host "DEBUG (Save CSV Test Windows): PathToRun is '$PathToRun'"
            Write-Host "DEBUG (Save CSV Test Windows): CurrentTempDir is '$CurrentTempDir'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) { throw "Script not found! Path: '$PathToRun'" }
            if (-not ($CurrentTempDir -and (Test-Path $CurrentTempDir -PathType Container))) { throw "Temp dir not found! TempDir: '$CurrentTempDir'" }
            
            $testCsvPath = Join-Path $CurrentTempDir "win_processes.csv"
            Write-Host "DEBUG (Save CSV Test Windows): Target CSV path is '$testCsvPath'"
            $Error.Clear(); $scriptOutput = $null
            try { $scriptOutput = & $PathToRun -OutputPath $testCsvPath -Verbose -ErrorAction Stop } catch { Write-Warning "Exception: $($_.Exception.ToString())" }
            if ($Error.Count -gt 0) { $Error | ForEach-Object { Write-Warning $_.ToString() } }
            
            $fileExists = Test-Path $testCsvPath -PathType Leaf
            Write-Host "DEBUG (Save CSV Test Windows): File exists result for '$testCsvPath': $fileExists"
            $fileExists | Should -Be $true

            if ($fileExists) {
                $fileContent = Get-Content $testCsvPath -ErrorAction SilentlyContinue
                $fileContent.Length | Should -BeGreaterThan 0 
                if ($mockProcesses) {
                    $csvFromFile = $fileContent | ConvertFrom-Csv
                    $csvFromFile.Count | Should -Be ($mockProcesses.Count)
                } else { Write-Warning "Save CSV Test (Windows): mockProcesses variable not found."}
            }
        }
        
        # Add other tests for JSON output, directory creation, etc., similar to the "Saves CSV" one.

        It "Verifies that mocks for Get-Process and Get-WmiObject were called (Windows)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            & $PathToRun -ErrorAction SilentlyContinue # Execute the script
            Assert-MockCalled -CommandName Get-Process -Exactly 1 -Scope It 
            Assert-MockCalled -CommandName Get-WmiObject -Times 2 -Scope It # Once for PerfData, once for PID 1005 owner fallback
        }
    }

    Context "Error Handling and Edge Cases (Windows)" {
        BeforeEach { # Ensure mocks are fresh or re-mock if needed
            $CurrentScriptPath = $script:SharedData.ScriptPathToTest
            if (-not ($CurrentScriptPath -and (Test-Path $CurrentScriptPath -PathType Leaf))) {
                throw "FATAL in BeforeEach (Windows Error Handling): ScriptPathToTest from script:SharedData is invalid: '$CurrentScriptPath'"
            }
            # Mocks from parent context's BeforeEach will generally apply unless overridden here.
        }

        It "Handles empty process list from Get-Process gracefully (Windows)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            Write-Host "DEBUG (Empty List Test Windows): PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) {
                throw "FATAL (Empty List Test Windows): Script to test is invalid or not found: '$PathToRun'"
            }
            Mock Get-Process { @() } -Verifiable # Override Get-Process mock
            Mock Get-WmiObject { @() } -Verifiable # Override WMI mock

            $WarningResult = $null
            $ScriptBlock = {
                $WarningPreference = 'Continue'
                & $PathToRun -ErrorAction SilentlyContinue 
            }
            Invoke-Command -ScriptBlock $ScriptBlock -WarningVariable WarningResult -ErrorVariable ErrorResult -ErrorAction SilentlyContinue
            $WarningResult.Message | Should -Match "No process information could be gathered"
        }
    }
}