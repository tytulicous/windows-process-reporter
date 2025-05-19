# tests/Get-ProcessReport.Tests.ps1

Describe "Get-ProcessReport.ps1" -Tags 'ProcessReport' {

    # $script:SharedData will be created and populated by BeforeAll
    # No need to pre-define it here if BeforeAll always runs first and creates it.
    # However, to avoid potential 'variable not found' if an It block somehow runs before BeforeAll (not Pester's design),
    # you could initialize it to $null or an empty hashtable here, though it's usually not necessary.
    # $script:SharedData = $null

    BeforeAll {
        # Initialize $script:SharedData as a new hashtable INSIDE BeforeAll
        $script:SharedData = @{
            ScriptPathToTest = $null
            TempDir          = $null
        }

        $RelativePathToScript = "..\Get-ProcessReport.ps1"
        $ScriptFile = $null
        try {
            $ScriptFile = (Resolve-Path (Join-Path $PSScriptRoot $RelativePathToScript) -ErrorAction Stop).Path
        }
        catch {
            Write-Error "FATAL in BeforeAll: Could not resolve script path. PSScriptRoot: '$PSScriptRoot', Relative: '$RelativePathToScript'. Error: $($_.Exception.Message)"
            throw
        }

        if (-not (Test-Path $ScriptFile -PathType Leaf)) {
            Write-Error "FATAL in BeforeAll: Resolved script path '$ScriptFile' does not exist or is not a file."
            throw
        }

        # Now assign to the property of the $script:SharedData hashtable
        $script:SharedData.ScriptPathToTest = $ScriptFile
        Write-Host "BeforeAll: Set script:SharedData.ScriptPathToTest to '$($script:SharedData.ScriptPathToTest)'"

        $script:SharedData.TempDir = Join-Path $env:TEMP "ProcessReporterTests_$(Get-Random)"
        if (-not (Test-Path $script:SharedData.TempDir)) {
            New-Item -ItemType Directory -Path $script:SharedData.TempDir -Force | Out-Null
        }
        Write-Host "BeforeAll: Set script:SharedData.TempDir to '$($script:SharedData.TempDir)'"
    }

    AfterAll {
        # Access the TempDir from the $script:SharedData hashtable
        if ($script:SharedData -and $script:SharedData.TempDir -and (Test-Path $script:SharedData.TempDir)) {
            Write-Host "AfterAll: Removing TempDir '$($script:SharedData.TempDir)'"
            Remove-Item $script:SharedData.TempDir -Recurse -Force
        }
    }

    Context "Core Functionality with Mocks" {
        $mockProcesses = $null # etc.

        BeforeEach {
            # Access paths from $script:SharedData
            $CurrentScriptPath = $script:SharedData.ScriptPathToTest # Note $script: prefix

            if (-not ($CurrentScriptPath -and (Test-Path $CurrentScriptPath -PathType Leaf))) {
                throw "FATAL in BeforeEach (Core): ScriptPathToTest from script:SharedData is invalid: '$CurrentScriptPath'"
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
            $PathToRun = $script:SharedData.ScriptPathToTest # Note $script: prefix
            Write-Host "DEBUG CSV Test: PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) { throw "Script not found in CSV Test! Path: '$PathToRun'" }
            
            $output = & $PathToRun -ErrorAction Stop
            $csvOutput = $output | ConvertFrom-Csv
            $csvOutput.Count | Should -Be ($mockProcesses.Count)
        }

        # ... Ensure ALL other It blocks and BeforeEach/AfterEach that need ScriptPathToTest or TempDir
        #     access them via $script:SharedData.ScriptPathToTest or $script:SharedData.TempDir
        # Example:
        It "Saves CSV report to specified -OutputPath" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $CurrentTempDir = $script:SharedData.TempDir
            # ...
            $testCsvPath = Join-Path $CurrentTempDir "test_processes.csv"
            & $PathToRun -OutputPath $testCsvPath -ErrorAction Stop
            # ...
        }
    }

    Context "Error Handling and Edge Cases" {
        BeforeEach {
            $CurrentScriptPath = $script:SharedData.ScriptPathToTest # Note $script: prefix
            if (-not ($CurrentScriptPath -and (Test-Path $CurrentScriptPath -PathType Leaf))) {
                throw "FATAL in BeforeEach (Error Handling): ScriptPathToTest from script:SharedData is invalid: '$CurrentScriptPath'"
            }
        }

        It "Handles empty process list from Get-Process gracefully (warns and exits)" {
            $PathToRun = $script:SharedData.ScriptPathToTest # Note $script: prefix
            Write-Host "DEBUG (Empty List Test): PathToRun is '$PathToRun'"
            if (-not ($PathToRun -and (Test-Path $PathToRun -PathType Leaf))) {
                throw "FATAL (Empty List Test): Script to test is invalid or not found: '$PathToRun'"
            }

            Mock Get-Process { @() } -ModuleName $PathToRun -Verifiable
            Mock Get-WmiObject { @() } -ModuleName $PathToRun -Verifiable
            
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
