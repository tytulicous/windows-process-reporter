# tests/Get-ProcessReport.Tests.ps1

# Import Pester explicitly if not auto-loaded or for clarity
# In Pester 5+, module auto-loading often handles this, but explicit is fine.
# If (Get-Module -Name Pester -ErrorAction SilentlyContinue) { Remove-Module Pester -Force }
# Install-Module Pester -Force -SkipPublisherCheck -Scope CurrentUser # If not already installed
# Import-Module Pester -RequiredVersion 5.0.0 # Or your desired version

$ScriptPath = Join-Path $PSScriptRoot "..\Get-ProcessReport.ps1" # Path to the script being tested

Describe "Get-ProcessReport.ps1" -Tags 'ProcessReport' {

    # Mock data
    $mockProcesses = @(
        [PSCustomObject]@{
            Id            = 1001
            ProcessName   = 'powershell'
            UserName      = 'TESTDOMAIN\User1'
            WorkingSet64  = 200MB
            CPU           = 120 # TotalSeconds - script uses WMI for Percent
        }
        [PSCustomObject]@{
            Id            = 1002
            ProcessName   = 'chrome'
            UserName      = 'TESTDOMAIN\User1'
            WorkingSet64  = 500MB
            CPU           = 300
        }
        [PSCustomObject]@{
            Id            = 1003
            ProcessName   = 'svchost'
            UserName      = 'NT AUTHORITY\SYSTEM'
            WorkingSet64  = 50MB
            CPU           = 60
        }
        [PSCustomObject]@{ # Process for which WMI CPU data might be missing
            Id            = 1004
            ProcessName   = 'explorer'
            UserName      = 'TESTDOMAIN\User1'
            WorkingSet64  = 150MB
            CPU           = 90
        }
        [PSCustomObject]@{ # Process with no initial UserName, testing WMI fallback
            Id            = 1005
            ProcessName   = 'System'
            UserName      = $null # Simulate Get-Process not returning user
            WorkingSet64  = 10MB
            CPU           = 10
        }
    )

    $mockWmiPerfData = @(
        [PSCustomObject]@{
            IDProcess            = 1001
            PercentProcessorTime = 10 # This is the value we expect
            Name                 = 'powershell'
        }
        [PSCustomObject]@{
            IDProcess            = 1002
            PercentProcessorTime = 25
            Name                 = 'chrome'
        }
        [PSCustomObject]@{
            IDProcess            = 1003
            PercentProcessorTime = 5
            Name                 = 'svchost'
        }
        # PID 1004 (explorer) deliberately missing to test default CPU 0
        [PSCustomObject]@{ # For PID 1005 to test WMI owner fallback
            IDProcess            = 1005
            Name                 = 'System'
            PercentProcessorTime = 1
            # Mock GetOwner() method for this object
            PSObject = @{
                Methods = @{
                    GetOwner = {
                        param()
                        return [PSCustomObject]@{
                            User   = 'SYSTEM'
                            Domain = 'NT AUTHORITY'
                        }
                    }
                }
            }
        }
    )
    
    $mockWmiProcessDataForOwner = @( # For PID 1005 to test WMI owner fallback
         [PSCustomObject]@{
            ProcessId = 1005
            # Mock GetOwner() method for this object
            PSObject = @{
                Methods = @{
                    GetOwner = {
                        param()
                        return [PSCustomObject]@{
                            User   = 'SYSTEM_WMI' # Differentiate from Get-Process
                            Domain = 'NT AUTHORITY'
                        }
                    }
                }
            }
        }
    )


    # Helper to create a temporary output file path
    $tempDir = Join-Path $env:TEMP "ProcessReporterTests"
    BeforeAll {
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }
    }
    AfterAll {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force
        }
    }

    Context "Core Functionality with Mocks" {
        # Mock Get-Process and Get-WmiObject for all tests in this context
        BeforeEach {
            Mock Get-Process { return $mockProcesses } -ParameterFilter { $IncludeUserName -eq $true }
            Mock Get-Process { return $mockProcesses } # Fallback if -IncludeUserName is not explicitly checked in mock
            
            Mock Get-WmiObject -MockWith {
                param($Class, $Query)
                if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') {
                    return $mockWmiPerfData
                }
                if ($Query -match "Win32_Process WHERE ProcessId = 1005") { # For specific owner lookup
                    return $mockWmiProcessDataForOwner | Where-Object {$_.ProcessId -eq 1005}
                }
                # Add more specific query mocks if needed for other PIDs or general queries
                return @() # Default empty for other WMI calls
            }
        }

        It "Generates CSV output to console by default" {
            $output = & $ScriptPath -ErrorAction Stop # Invoke the script
            $csvOutput = $output | ConvertFrom-Csv

            $csvOutput.Count | Should -Be $mockProcesses.Count # Assuming all mocked processes are reported
            $csvOutput[0].PID | Should -Be '1002' # chrome (highest CPU in mock data after sorting)
            $csvOutput[0].Name | Should -Be 'chrome'
            $csvOutput[0].User | Should -Be 'TESTDOMAIN\User1'
            $csvOutput[0].CPU_Percent | Should -Be '25'
            $csvOutput[0].Memory_MB | Should -Be ([math]::Round(500MB / 1MB, 2)).ToString() # ConvertTo-Csv makes everything string

            # Test a process with missing WMI CPU data (explorer, PID 1004)
            ($csvOutput | Where-Object PID -eq '1004').CPU_Percent | Should -Be '0'

            # Test a process with WMI owner fallback (System, PID 1005)
            ($csvOutput | Where-Object PID -eq '1005').User | Should -Be 'NT AUTHORITY\SYSTEM_WMI'
        }

        It "Generates JSON output to console when -Format json is specified" {
            $output = & $ScriptPath -Format json -ErrorAction Stop
            $jsonOutput = $output | ConvertFrom-Json

            $jsonOutput.Count | Should -Be $mockProcesses.Count
            $jsonOutput[0].PID | Should -Be 1002 # chrome
            $jsonOutput[0].Name | Should -Be 'chrome'
            $jsonOutput[0].User | Should -Be 'TESTDOMAIN\User1'
            $jsonOutput[0].CPU_Percent | Should -Be 25
            $jsonOutput[0].Memory_MB | Should -Be ([math]::Round(500MB / 1MB, 2))
            
            # Test a process with missing WMI CPU data (explorer, PID 1004)
            ($jsonOutput | Where-Object PID -eq 1004).CPU_Percent | Should -Be 0

            # Test a process with WMI owner fallback (System, PID 1005)
            ($jsonOutput | Where-Object PID -eq 1005).User | Should -Be 'NT AUTHORITY\SYSTEM_WMI'
        }

        It "Saves CSV report to specified -OutputPath" {
            $testCsvPath = Join-Path $tempDir "test_processes.csv"
            & $ScriptPath -OutputPath $testCsvPath -ErrorAction Stop

            Test-Path $testCsvPath | Should -Be $true
            $fileContent = Get-Content $testCsvPath | ConvertFrom-Csv
            $fileContent.Count | Should -Be $mockProcesses.Count
            $fileContent[0].PID | Should -Be '1002' # chrome
        }

        It "Saves JSON report to specified -OutputPath when -Format json is specified" {
            $testJsonPath = Join-Path $tempDir "test_processes.json"
            & $ScriptPath -Format json -OutputPath $testJsonPath -ErrorAction Stop

            Test-Path $testJsonPath | Should -Be $true
            $fileContent = Get-Content $testJsonPath | ConvertFrom-Json
            $fileContent.Count | Should -Be $mockProcesses.Count
            $fileContent[0].PID | Should -Be 1002 # chrome
        }
        
        It "Creates parent directory if OutputPath directory does not exist" {
            $nestedTempDir = Join-Path $tempDir "NewSubDir"
            $testCsvPath = Join-Path $nestedTempDir "nested_processes.csv"
            
            # Ensure the directory does NOT exist before the test
            if (Test-Path $nestedTempDir) { Remove-Item $nestedTempDir -Recurse -Force }

            # Mock New-Item for verification if needed, but actual creation is fine too
            # For this test, we'll check for actual creation
            & $ScriptPath -OutputPath $testCsvPath -ErrorAction Stop

            Test-Path $testCsvPath | Should -Be $true
            Test-Path $nestedTempDir | Should -Be $true # Check directory was created
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Handles empty process list from Get-Process gracefully (should warn and output empty or headers only)" {
            # Mock Get-Process to return an empty array
            Mock Get-Process { @() } -ParameterFilter { $IncludeUserName -eq $true }
            Mock Get-Process { @() }
            Mock Get-WmiObject -MockWith { @() } # Empty WMI data as well

            # The script exits with 1 and writes a warning. Pester can't easily catch `exit` directly
            # without more complex setups. We can check for the warning.
            # This test will verify the warning. The script is expected to Write-Warning and then exit.
            # Pester 5+ has `Should -Throw` but `exit` isn't a standard exception.
            # We will check for warning output.
            $WarningResult = Invoke-Command {
                $WarningPreference = 'Continue' # Ensure warnings are collected
                & $ScriptPath
            } -WarningVariable ScriptWarnings -ErrorAction SilentlyContinue # SilentlyContinue for exit code

            $ScriptWarnings.Count | Should -BeGreaterThanOrEqual 1
            $ScriptWarnings.Message | Should -Match "No process information could be gathered"
            
            # Because the script exits, $WarningResult will likely be empty or reflect partial output before exit
        }

        It "Handles Get-WmiObject for CPU returning nothing (CPU should be 0)" {
            Mock Get-Process { return $mockProcesses | Select-Object -First 1 } -ParameterFilter { $IncludeUserName }
            Mock Get-Process { return $mockProcesses | Select-Object -First 1 }
            Mock Get-WmiObject -MockWith { param($Class) if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') { return @() } } # Empty WMI CPU data

            $output = & $ScriptPath -Format json
            $jsonOutput = $output | ConvertFrom-Json
            $jsonOutput.CPU_Percent | Should -Be 0
        }

        # Parameter validation for -Format is handled by ValidateSet,
        # so script won't run with invalid. This could test default if not specified.
        It "Defaults to CSV format if -Format is not specified" {
             Mock Get-Process { return $mockProcesses | Select-Object -First 1 } -ParameterFilter { $IncludeUserName }
             Mock Get-Process { return $mockProcesses | Select-Object -First 1 }
             Mock Get-WmiObject -MockWith {
                param($Class)
                if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') {
                    return $mockWmiPerfData | Where-Object {$_.IDProcess -eq ($mockProcesses[0].Id)}
                }
                return @()
            }

            $output = & $ScriptPath
            { $output | ConvertFrom-Csv } | Should -Not -Throw # If it's CSV, this won't throw
            $csvOutput = $output | ConvertFrom-Csv
            $csvOutput.PID | Should -Not -BeNullOrEmpty
        }
    }

    # More tests could include:
    # - Testing with extremely long process names or user names.
    # - Testing different locales if string formatting is sensitive (less likely here).
    # - Testing behavior when write permission is denied for OutputPath (would require mocking Set-Content or filesystem interaction).
}
