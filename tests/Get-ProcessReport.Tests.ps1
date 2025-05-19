# tests/Get-ProcessReport.Tests.ps1

Describe "Get-ProcessReport.ps1" -Tags 'ProcessReport' {

    $script:SharedData = $null # Will be initialized in BeforeAll

    BeforeAll {
        $script:SharedData = @{
            ScriptPathToTest = $null
            TempDir          = $null
        }
        # ... (rest of BeforeAll as before, setting $script:SharedData.ScriptPathToTest and $script:SharedData.TempDir)
        $RelativePathToScript = "..\Get-ProcessReport.ps1"
        $ScriptFile = $null
        try {
            $ScriptFile = (Resolve-Path (Join-Path $PSScriptRoot $RelativePathToScript) -ErrorAction Stop).Path
        } catch { Write-Error "FATAL ..."; throw }
        if (-not (Test-Path $ScriptFile -PathType Leaf)) { Write-Error "FATAL ..."; throw }
        $script:SharedData.ScriptPathToTest = $ScriptFile
        Write-Host "BeforeAll: Set script:SharedData.ScriptPathToTest to '$($script:SharedData.ScriptPathToTest)'"
        $script:SharedData.TempDir = Join-Path $env:TEMP "ProcessReporterTests_$(Get-Random)"
        if (-not (Test-Path $script:SharedData.TempDir)) { New-Item -ItemType Directory -Path $script:SharedData.TempDir -Force | Out-Null }
        Write-Host "BeforeAll: Set script:SharedData.TempDir to '$($script:SharedData.TempDir)'"
    }

    AfterAll {
        if ($script:SharedData -and $script:SharedData.TempDir -and (Test-Path $script:SharedData.TempDir)) {
            Remove-Item $script:SharedData.TempDir -Recurse -Force
        }
    }

    Context "Core Functionality with Mocks" {
        $mockProcesses = $null # etc.

        BeforeEach {
            $CurrentScriptPath = $script:SharedData.ScriptPathToTest # Still useful to have the path for other things if needed
            if (-not ($CurrentScriptPath -and (Test-Path $CurrentScriptPath -PathType Leaf))) {
                throw "FATAL in BeforeEach (Core): ScriptPathToTest from script:SharedData is invalid: '$CurrentScriptPath'"
            }

            # Mock data setup (same as before)...
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

            # REMOVE -ModuleName from Mocks
            Mock Get-Process { param($IncludeUserName) return $mockProcesses } -Verifiable
            Mock Get-WmiObject -MockWith {
                param($Class, $Query)
                # Write-Host "DEBUG MOCK Get-WmiObject: Class='$Class', Query='$Query'" # Uncomment for deep mock debug
                if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') { return $mockWmiPerfData }
                if ($Query -match "Win32_Process WHERE ProcessId = 1005") { return $mockWmiProcessDataForOwnerFallback | Where-Object {$_.ProcessId -eq 1005} }
                if ($Query -match "Win32_Process WHERE ProcessId") { return @() } # General catch
                return @() # Default empty
            } -Verifiable
        }

        It "Generates CSV output to console by default" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            # ... (debugging Write-Host and if checks as before) ...
            Write-Host "DEBUG CSV Test: PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) { throw "Script not found in CSV Test! Path: '$PathToRun'" }
            
            $output = & $PathToRun -ErrorAction Stop
            $csvOutput = $output | ConvertFrom-Csv
            $csvOutput.Count | Should -Be ($mockProcesses.Count)
            # ... other assertions
        }

        It "Saves CSV report to specified -OutputPath" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $CurrentTempDir = $script:SharedData.TempDir
            # ... (debugging and test logic as in the previous good version for this 'It' block) ...
            Write-Host "DEBUG (Save CSV Test): PathToRun is '$PathToRun'"; # etc.
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) { throw "Script not found!" }
            if (-not ($CurrentTempDir -and (Test-Path $CurrentTempDir -PathType Directory))) { throw "Temp dir not found!" }
            $testCsvPath = Join-Path $CurrentTempDir "test_processes.csv"
            Write-Host "DEBUG (Save CSV Test): Target CSV path is '$testCsvPath'"
            $Error.Clear(); $scriptOutput = $null
            Write-Host "DEBUG (Save CSV Test): Executing script: & '$PathToRun' -OutputPath '$testCsvPath' -Verbose"
            try { $scriptOutput = & $PathToRun -OutputPath $testCsvPath -Verbose -ErrorAction Stop } catch { Write-Warning "Exception: $($_.Exception.ToString())" }
            if ($Error.Count -gt 0) { $Error | ForEach-Object { Write-Warning $_.ToString() } }
            $fileExists = Test-Path $testCsvPath -PathType Leaf
            Write-Host "DEBUG (Save CSV Test): File exists result: $fileExists"
            $fileExists | Should -Be $true
            if ($fileExists) {
                $fileContent = Get-Content $testCsvPath -ErrorAction SilentlyContinue
                $fileContent.Length | Should -BeGreaterThan 0
                if ($mockProcesses) {
                    $csvFromFile = $fileContent | ConvertFrom-Csv
                    $csvFromFile.Count | Should -Be ($mockProcesses.Count)
                }
            }
        }
        
        # ... other 'It' blocks, ensuring -ModuleName is removed from their mocks if any ...

        It "Verifies that mocks for Get-Process and Get-WmiObject were called" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            & $PathToRun -ErrorAction SilentlyContinue
            # REMOVE -ModuleName from Assert-MockCalled
            Assert-MockCalled -CommandName Get-Process -Exactly 1 -Scope It
            Assert-MockCalled -CommandName Get-WmiObject -Times 2 -Scope It # Adjust count as per script logic
        }
    }

    Context "Error Handling and Edge Cases" {
        BeforeEach {
            $CurrentScriptPath = $script:SharedData.ScriptPathToTest
            if (-not ($CurrentScriptPath -and (Test-Path $CurrentScriptPath -PathType Leaf))) {
                throw "FATAL in BeforeEach (Error Handling): ScriptPathToTest from script:SharedData is invalid: '$CurrentScriptPath'"
            }
            # Any mocks specific to this context would also omit -ModuleName
        }

        It "Handles empty process list from Get-Process gracefully (warns and exits)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            # ... (debugging Write-Host and if checks as before) ...
            Write-Host "DEBUG (Empty List Test): PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) { throw "Script not found!" }

            # REMOVE -ModuleName from Mocks
            Mock Get-Process { @() } -Verifiable
            Mock Get-WmiObject { @() } -Verifiable
            
            $WarningResult = $null
            $ScriptBlock = {
                $WarningPreference = 'Continue'
                & $PathToRun -ErrorAction SilentlyContinue 
            }
            Invoke-Command -ScriptBlock $ScriptBlock -WarningVariable WarningResult -ErrorVariable ErrorResult -ErrorAction SilentlyContinue
            $WarningResult.Message | Should -Match "No process information could be gathered"
        }
        # ... other 'It' blocks, ensuring -ModuleName is removed from their mocks if any ...
    }
}
