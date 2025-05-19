# tests/Get-ProcessReport.Tests.ps1

$ScriptPath = Join-Path $PSScriptRoot "..\Get-ProcessReport.ps1"

Describe "Get-ProcessReport.ps1" -Tags 'ProcessReport' {

    # Declare $tempDir here so it's in the Describe scope
    $tempDir = $null

    BeforeAll {
        # Initialize $tempDir within BeforeAll using $script: to make it accessible
        # to other blocks within this Describe if needed, or just use a local var if only for Before/AfterAll.
        # For consistency with It blocks, let's set it in the script scope of the Describe block.
        $script:tempDir = Join-Path $env:TEMP "ProcessReporterTests_$(Get-Random)"
        if (-not (Test-Path $script:tempDir)) {
            New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
        }
    }

    AfterAll {
        # Access $tempDir from the script scope of the Describe block
        if ($script:tempDir -and (Test-Path $script:tempDir)) {
            Remove-Item $script:tempDir -Recurse -Force
        }
    }

    Context "Core Functionality with Mocks" {
        # Mock data variables
        $mockProcesses = $null
        $mockWmiPerfData = $null
        $mockWmiProcessDataForOwnerFallback = $null

        BeforeEach {
            # $tempDir is now accessible from the Describe scope ($script:tempDir)
            # No need to redefine it here if the It blocks will use $script:tempDir

            # Define base mock data for each test run
            $mockProcesses = @(
                # ... (your mock data as before)
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
                param()
                return [PSCustomObject]@{ User = 'SYSTEM_WMI_Fallback'; Domain = 'NT AUTHORITY' }
            } -Force
            $mockWmiProcessDataForOwnerFallback = @( $mockSystemWmiProcessForOwnerObject )

            Mock Get-Process { param($IncludeUserName) return $mockProcesses } -ModuleName $ScriptPath -Verifiable
            Mock Get-WmiObject -ModuleName $ScriptPath -MockWith {
                param($Class, $Query)
                if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') { return $mockWmiPerfData }
                if ($Query -match "Win32_Process WHERE ProcessId = 1005") { return $mockWmiProcessDataForOwnerFallback | Where-Object {$_.ProcessId -eq 1005} }
                if ($Query -match "Win32_Process WHERE ProcessId") { return @() }
                return @()
            } -Verifiable
        }

        It "Generates CSV output to console by default" {
            $output = & $ScriptPath -ErrorAction Stop
            $csvOutput = $output | ConvertFrom-Csv
            $csvOutput.Count | Should -Be ($mockProcesses.Count)
            $csvOutput[0].PID | Should -Be '1002'
            ($csvOutput | Where-Object PID -eq '1005').User | Should -Be 'NT AUTHORITY\SYSTEM_WMI_Fallback'
        }

        It "Generates JSON output to console when -Format json is specified" {
            $output = & $ScriptPath -Format json -ErrorAction Stop
            $jsonOutput = $output | ConvertFrom-Json
            $jsonOutput.Count | Should -Be ($mockProcesses.Count)
            $jsonOutput[0].PID | Should -Be 1002
            ($jsonOutput | Where-Object PID -eq 1005).User | Should -Be 'NT AUTHORITY\SYSTEM_WMI_Fallback'
        }

        It "Saves CSV report to specified -OutputPath" {
            # Use $script:tempDir here
            $testCsvPath = Join-Path $script:tempDir "test_processes.csv"
            & $ScriptPath -OutputPath $testCsvPath -ErrorAction Stop
            Test-Path $testCsvPath | Should -Be $true
        }

        It "Saves JSON report to specified -OutputPath when -Format json is specified" {
            # Use $script:tempDir here
            $testJsonPath = Join-Path $script:tempDir "test_processes.json"
            & $ScriptPath -Format json -OutputPath $testJsonPath -ErrorAction Stop
            Test-Path $testJsonPath | Should -Be $true
        }
        
        It "Creates parent directory if OutputPath directory does not exist" {
            # Use $script:tempDir for the base
            $nestedTempParentDir = Join-Path $script:tempDir "NewSubDir_$(Get-Random)"
            $testCsvPath = Join-Path $nestedTempParentDir "nested_processes.csv"
            if (Test-Path $nestedTempParentDir) { Remove-Item $nestedTempParentDir -Recurse -Force }
            & $ScriptPath -OutputPath $testCsvPath -ErrorAction Stop
            Test-Path $testCsvPath | Should -Be $true
            Test-Path $nestedTempParentDir | Should -Be $true
        }

        It "Verifies that mocks for Get-Process and Get-WmiObject were called" {
            & $ScriptPath -ErrorAction SilentlyContinue
            Assert-MockCalled -CommandName Get-Process -Exactly 1 -Scope It
            Assert-MockCalled -CommandName Get-WmiObject -Times 2 -Scope It 
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Handles empty process list from Get-Process gracefully (warns and exits)" {
            Mock Get-Process { @() } -ModuleName $ScriptPath -Verifiable
            Mock Get-WmiObject { @() } -ModuleName $ScriptPath -Verifiable
            $WarningResult = $null
            $ScriptBlock = {
                $WarningPreference = 'Continue'
                & $ScriptPath -ErrorAction SilentlyContinue
            }
            Invoke-Command -ScriptBlock $ScriptBlock -WarningVariable WarningResult -ErrorVariable ErrorResult -ErrorAction SilentlyContinue
            $WarningResult.Message | Should -Match "No process information could be gathered"
        }

        It "Handles Get-WmiObject for CPU returning nothing (CPU should be 0)" {
            $singleProcess = ([PSCustomObject]@{ Id = 2001; ProcessName = 'notepad'; UserName = 'TESTDOMAIN\User2'; WorkingSet64 = 50MB; CPU = 10 })
            Mock Get-Process { return @($singleProcess) } -ModuleName $ScriptPath
            Mock Get-WmiObject -ModuleName $ScriptPath -MockWith {
                param($Class)
                if ($Class -eq 'Win32_PerfFormattedData_PerfProc_Process') { return @() }
                if ($Class -eq 'Win32_Process' -and $singleProcess.UserName -eq $null) { return @() } 
                return @()
            }
            $output = & $ScriptPath -Format json -ErrorAction Stop
            $jsonOutput = $output | ConvertFrom-Json
            $jsonOutput.CPU_Percent | Should -Be 0
        }

        It "Defaults to CSV format if -Format is not specified" {
            # Mocks from parent BeforeEach will apply.
            # We need to ensure $mockProcesses is available or re-mock here if its structure from parent BeforeEach is not suitable.
            # For this test, relying on the parent's BeforeEach for mocks is okay.
            $output = & $ScriptPath -ErrorAction Stop
            { $output | ConvertFrom-Csv } | Should -Not -Throw
            $csvOutput = $output | ConvertFrom-Csv
            $csvOutput[0].PID | Should -Not -BeNullOrEmpty
        }
    }
}
