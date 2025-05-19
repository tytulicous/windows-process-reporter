# tests/Get-ProcessReport.Tests.ps1

$ScriptPath = Join-Path $PSScriptRoot "..\Get-ProcessReport.ps1"

Describe "Get-ProcessReport.ps1" -Tags 'ProcessReport' {

    # Helper to create a temporary output file path
    $tempDir = Join-Path $env:TEMP "ProcessReporterTests_$(Get-Random)" # Add random to avoid clashes
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

        # Mock data will be defined and methods added within BeforeEach
        # to ensure clean state for each test and proper application of Add-Member
        $mockProcesses = $null
        $mockWmiPerfData = $null
        $mockWmiProcessDataForOwnerFallback = $null

        BeforeEach {
            # Define base mock data for each test run
            $mockProcesses = @(
                [PSCustomObject]@{
                    Id            = 1001
                    ProcessName   = 'powershell'
                    UserName      = 'TESTDOMAIN\User1'
                    WorkingSet64  = 200MB
                    CPU           = 120
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
                [PSCustomObject]@{
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

            # --- Mock WMI Performance Data ---
            $mockSystemWmiPerfObject = [PSCustomObject]@{ IDProcess = 1005; Name = 'System'; PercentProcessorTime = 1 }
            # No GetOwner needed on Win32_PerfFormattedData_PerfProc_Process objects

            $mockWmiPerfData = @(
                [PSCustomObject]@{ IDProcess = 1001; PercentProcessorTime = 10; Name = 'powershell' }
                [PSCustomObject]@{ IDProcess = 1002; PercentProcessorTime = 25; Name = 'chrome' }
                [PSCustomObject]@{ IDProcess = 1003; PercentProcessorTime = 5; Name = 'svchost' }
                $mockSystemWmiPerfObject
            )

            # --- Mock WMI Process Data for Owner Fallback (for PID 1005) ---
            $mockSystemWmiProcessForOwnerObject = [PSCustomObject]@{ ProcessId = 1005; Name = 'System' } # Add Name for consistency
            Add-Member -InputObject $mockSystemWmiProcessForOwnerObject -MemberType ScriptMethod -Name GetOwner -Value {
                param()
                # Write-Verbose "Mocked GetOwner on Win32_Process for $($this.ProcessId) called" # For debugging tests
                return [PSCustomObject]@{
                    User   = 'SYSTEM_WMI_Fallback'
                    Domain = 'NT AUTHORITY'
                }
            } -Force

            $mockWmiProcessDataForOwnerFallback = @(
                $mockSystemWmiProcessForOwnerObject
            )

            # Apply mocks
            Mock Get-Process { param($IncludeUserName) return $mockProcesses } -ModuleName $ScriptPath -Verifiable # Mock for the script's scope
            
            Mock Get-WmiObject -ModuleName $ScriptPath -MockWith { # Mock for the script's scope
                param($Class, $Query, $ComputerName, $Namespace, $Filter, $Property) # Capture all potential params
                
                # Write-Verbose "Mock Get-WmiObject called with Class: '$Class', Query: '$Query'" # For debugging tests

                if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') {
                    # Write-Verbose "Returning mockWmiPerfData" # For debugging tests
                    return $mockWmiPerfData
                }
                if ($Query -match "Win32_Process WHERE ProcessId = 1005") {
                    # Write-Verbose "Returning mockWmiProcessDataForOwnerFallback for PID 1005" # For debugging tests
                    return $mockWmiProcessDataForOwnerFallback | Where-Object {$_.ProcessId -eq 1005}
                }
                if ($Query -match "Win32_Process WHERE ProcessId") { # General catch for other PID owner lookups if any
                    # Write-Verbose "Returning empty for other Win32_Process query: $Query" # For debugging tests
                    return @() # Default empty for other specific Win32_Process queries
                }
                # Write-Verbose "Returning default empty for unhandled WMI call" # For debugging tests
                return @() # Default empty for other WMI calls
            } -Verifiable
        }

        It "Generates CSV output to console by default" {
            $output = & $ScriptPath -ErrorAction Stop
            $csvOutput = $output | ConvertFrom-Csv

            $csvOutput.Count | Should -Be ($mockProcesses.Count) # Expecting all mocked processes to be reported
            $csvOutput[0].PID | Should -Be '1002' # chrome (highest CPU in mock data after sorting)
            $csvOutput[0].Name | Should -Be 'chrome'
            $csvOutput[0].User | Should -Be 'TESTDOMAIN\User1'
            $csvOutput[0].CPU_Percent | Should -Be '25' # From mockWmiPerfData
            $csvOutput[0].Memory_MB | Should -Be ([math]::Round(500MB / 1MB, 2)).ToString()

            ($csvOutput | Where-Object PID -eq '1004').CPU_Percent | Should -Be '0' # explorer, no WMI CPU data
            ($csvOutput | Where-Object PID -eq '1005').User | Should -Be 'NT AUTHORITY\SYSTEM_WMI_Fallback' # System, from WMI GetOwner fallback
        }

        It "Generates JSON output to console when -Format json is specified" {
            $output = & $ScriptPath -Format json -ErrorAction Stop
            $jsonOutput = $output | ConvertFrom-Json

            $jsonOutput.Count | Should -Be ($mockProcesses.Count)
            $jsonOutput[0].PID | Should -Be 1002 # chrome
            $jsonOutput[0].CPU_Percent | Should -Be 25
            ($jsonOutput | Where-Object PID -eq 1004).CPU_Percent | Should -Be 0
            ($jsonOutput | Where-Object PID -eq 1005).User | Should -Be 'NT AUTHORITY\SYSTEM_WMI_Fallback'
        }

        It "Saves CSV report to specified -OutputPath" {
            $testCsvPath = Join-Path $tempDir "test_processes.csv"
            & $ScriptPath -OutputPath $testCsvPath -ErrorAction Stop

            Test-Path $testCsvPath | Should -Be $true
            $fileContent = Get-Content $testCsvPath | ConvertFrom-Csv
            $fileContent.Count | Should -Be ($mockProcesses.Count)
            $fileContent[0].PID | Should -Be '1002'
        }

        It "Saves JSON report to specified -OutputPath when -Format json is specified" {
            $testJsonPath = Join-Path $tempDir "test_processes.json"
            & $ScriptPath -Format json -OutputPath $testJsonPath -ErrorAction Stop

            Test-Path $testJsonPath | Should -Be $true
            $fileContent = Get-Content $testJsonPath | ConvertFrom-Json
            $fileContent.Count | Should -Be ($mockProcesses.Count)
            $fileContent[0].PID | Should -Be 1002
        }
        
        It "Creates parent directory if OutputPath directory does not exist" {
            $nestedTempDir = Join-Path $tempDir "NewSubDir_$(Get-Random)" # Unique subdir
            $testCsvPath = Join-Path $nestedTempDir "nested_processes.csv"
            
            if (Test-Path $nestedTempDir) { Remove-Item $nestedTempDir -Recurse -Force }

            & $ScriptPath -OutputPath $testCsvPath -ErrorAction Stop

            Test-Path $testCsvPath | Should -Be $true
            Test-Path $nestedTempDir | Should -Be $true
        }

        # Verify that mocks were called
        It "Verifies that mocks for Get-Process and Get-WmiObject were called" {
            & $ScriptPath -ErrorAction SilentlyContinue # Run the script
            Assert-MockCalled -CommandName Get-Process -Exactly ($mockProcesses.Count + 1) # Once for initial Get-Process, then per process in WMI fallback if needed
                                                                                        # Initial Get-Process (1 call), then one Get-WmiObject for each process's owner if username is null
                                                                                        # Given the current main script logic for user fallback:
                                                                                        # 1 call to Get-Process -IncludeUserName
                                                                                        # For process 1005 (username null), 1 call to Get-WmiObject for Win32_Process
                                                                                        # So, Get-Process should be called once.
                                                                                        # Get-WmiObject will be called once for PerfData, and once for Win32_Process for PID 1005.
            Assert-MockCalled -CommandName Get-Process -Exactly 1 -Scope It # Called once for the main data gathering
            Assert-MockCalled -CommandName Get-WmiObject -Times 2 -Scope It # Once for PerfData, once for PID 1005 owner
                                                                            # This count needs to be precise based on script logic
        }
    }

    Context "Error Handling and Edge Cases" {
        # No need to re-define mocks here if they are general enough or if we re-mock specifically.
        # The BeforeEach from the parent Context will apply unless overridden.

        It "Handles empty process list from Get-Process gracefully (warns and exits)" {
            Mock Get-Process { @() } -ModuleName $ScriptPath -Verifiable
            Mock Get-WmiObject { @() } -ModuleName $ScriptPath -Verifiable # Ensure WMI also returns nothing

            $WarningResult = $null
            $ScriptBlock = {
                $WarningPreference = 'Continue' # Ensure warnings are collected
                & $ScriptPath -ErrorAction SilentlyContinue # Allow script to attempt exit
            }
            Invoke-Command -ScriptBlock $ScriptBlock -WarningVariable WarningResult -ErrorVariable ErrorResult -ErrorAction SilentlyContinue
            
            $WarningResult.Message | Should -Match "No process information could be gathered"
            # The script itself calls 'exit 1', which Pester doesn't catch as a PowerShell terminating error.
            # We check the warning. If using Pester's -PassThru with Invoke-Pester, the overall run might show failure if script errors.
        }

        It "Handles Get-WmiObject for CPU returning nothing (CPU should be 0)" {
            # Mock Get-Process to return just one process for simplicity
            $singleProcess = $mockProcesses[0] # Use a copy of one of the standard mocks
            Mock Get-Process { return @($singleProcess) } -ModuleName $ScriptPath

            # Mock Get-WmiObject to return empty for PerfData
            Mock Get-WmiObject -ModuleName $ScriptPath -MockWith {
                param($Class)
                if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') { return @() }
                # Handle potential owner lookup for this single process if its UserName were null
                if ($Class -eq 'Win32_Process' -and $singleProcess.UserName -eq $null) { return @() } 
                return @()
            }

            $output = & $ScriptPath -Format json -ErrorAction Stop
            $jsonOutput = $output | ConvertFrom-Json
            $jsonOutput.CPU_Percent | Should -Be 0
        }

        It "Defaults to CSV format if -Format is not specified" {
             # Mocks from BeforeEach should be sufficient here, or re-mock if more specific control is needed
             # For this test, we'll rely on the BeforeEach mocks.

            $output = & $ScriptPath -ErrorAction Stop
            { $output | ConvertFrom-Csv } | Should -Not -Throw
            $csvOutput = $output | ConvertFrom-Csv
            $csvOutput[0].PID | Should -Not -BeNullOrEmpty
        }
    }
}
