# macos/tests/Get-MacProcessReport.Tests.ps1

Write-Host "DEBUG_TOP: PSScriptRoot is '$PSScriptRoot'"
Write-Host "DEBUG_TOP: Current Directory is '$(Get-Location)'"
$ScriptPath = Join-Path $PSScriptRoot "..\Get-MacProcessReport.ps1"
Write-Host "DEBUG_TOP: Calculated ScriptPath is '$ScriptPath'"

Describe "Get-MacProcessReport.ps1 (macOS)" -Tags 'ProcessReport', 'macOS' {

    $script:SharedData = $null # Will be initialized in BeforeAll

    BeforeAll {
        Write-Host "DEBUG_BeforeAll: PSScriptRoot is '$PSScriptRoot'"
        Write-Host "DEBUG_BeforeAll: ScriptPath (from top scope) is '$ScriptPath'"

        $script:SharedData = @{
            ScriptPathToTest = $null
            TempDir          = $null
        }
        try {
            # Ensure $ScriptPath is not empty before trying to resolve it
            if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
                Write-Error "FATAL_BeforeAll: \$ScriptPath is null or empty before Resolve-Path. Value: '$ScriptPath'. PSScriptRoot was '$PSScriptRoot' at top."
                throw "FATAL_BeforeAll: ScriptPath was null or empty."
            }
            Write-Host "DEBUG_BeforeAll: Attempting Resolve-Path for: '$ScriptPath'"
            $script:SharedData.ScriptPathToTest = (Resolve-Path $ScriptPath -ErrorAction Stop).Path
        } catch {
            # Log the state of $ScriptPath if the try block fails
            Write-Error "FATAL_BeforeAll: Could not resolve Mac script path '$ScriptPath' (this is \$ScriptPath from the outer scope). Error: $($_.Exception.Message)"
            throw # Re-throw the original exception or a custom one
        }

        if (-not (Test-Path $script:SharedData.ScriptPathToTest -PathType Leaf)) {
            Write-Error "FATAL_BeforeAll: Mac script to test not found at '$($script:SharedData.ScriptPathToTest)'"
            throw
        }
        Write-Host "BeforeAll (macOS): ScriptPathToTest = '$($script:SharedData.ScriptPathToTest)'"

        $script:SharedData.TempDir = Join-Path $env:TEMP "MacProcessReporterTests_$(Get-Random)"
        if (-not (Test-Path $script:SharedData.TempDir -PathType Container)) {
            New-Item -ItemType Directory -Path $script:SharedData.TempDir -Force -ErrorAction Stop | Out-Null
        }
        Write-Host "BeforeAll (macOS): TempDir = '$($script:SharedData.TempDir)'"
    }

    # ... rest of your tests ...
    # (Your AfterAll and Context blocks remain the same)
    AfterAll {
        if ($script:SharedData -and $script:SharedData.TempDir -and (Test-Path $script:SharedData.TempDir -PathType Container)) {
            Remove-Item $script:SharedData.TempDir -Recurse -Force
        }
    }

    Context "Core Functionality with Mocks (macOS)" {
        $mockPsOutput_Header = "USER               PID %CPU   RSS COMM" # Match actual ps header
        $mockPsOutput_Data = @(
            "root                 1  0.2 20480 launchd",
            "jdoe              1234  5.5 512000 SomeApp",
            "jdoe              5678 12.1 102400 pwsh",
            "_mdnsresponder   234  0.0  8192 mDNSResponder",
            "anotheruser       901  0.8 30720 UserEventAgent" # Process with a different user
        )
        $mockPsOutput_Full = @($mockPsOutput_Header) + $mockPsOutput_Data

        BeforeEach {
            $PathToRun = $script:SharedData.ScriptPathToTest # Used for invoking the script
            Mock ps {
                param($ArgumentList)
                Write-Verbose "Mock 'ps' called with args: $ArgumentList"
                return $mockPsOutput_Full
            } -Verifiable
        }

        It "Generates CSV output to console by default (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $output = & $PathToRun -ErrorAction Stop
            $csvOutput = $output | ConvertFrom-Csv

            $csvOutput.Count | Should -Be $mockPsOutput_Data.Count
            $firstDataProc = $mockPsOutput_Data[1] 
            $parsedFirstDataProc = $firstDataProc -match '^\s*(?<user>\S+)\s+(?<pid>\d+)\s+(?<cpu>[\d\.]+)\s+(?<rss>\d+)\s+(?<name>.+)$'
            
            $csvOutput[0].PID | Should -Be '5678'
            $csvOutput[0].Name | Should -Be 'pwsh'
            $csvOutput[0].User | Should -Be 'jdoe'
            $csvOutput[0].CPU_Percent | Should -Be '12.1'
            $csvOutput[0].Memory_MB | Should -Be ([math]::Round(102400 / 1024, 2)).ToString() 
        }

        It "Generates JSON output to console when -Format json is specified (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $output = & $PathToRun -Format json -ErrorAction Stop
            $jsonOutput = $output | ConvertFrom-Json

            $jsonOutput.Count | Should -Be $mockPsOutput_Data.Count
            $jsonOutput[0].PID | Should -Be 5678 
            $jsonOutput[0].CPU_Percent | Should -Be 12.1
            $jsonOutput[0].Memory_MB | Should -Be ([math]::Round(102400 / 1024, 2))
        }

        It "Saves CSV report to specified -OutputPath (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $CurrentTempDir = $script:SharedData.TempDir
            $testCsvPath = Join-Path $CurrentTempDir "mac_processes.csv"

            & $PathToRun -OutputPath $testCsvPath -ErrorAction Stop

            Test-Path $testCsvPath -PathType Leaf | Should -Be $true
            $fileContent = Get-Content $testCsvPath | ConvertFrom-Csv
            $fileContent.Count | Should -Be $mockPsOutput_Data.Count
            $fileContent[0].PID | Should -Be '5678'
        }
        
        It "Handles empty or minimal 'ps' output (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            Mock ps { return @($mockPsOutput_Header) } 
            
            $WarningOutput = Invoke-Command {
                $WarningPreference = 'Continue'
                & $PathToRun -ErrorAction SilentlyContinue
            } -WarningVariable ScriptWarnings -ErrorAction SilentlyContinue

            $ScriptWarnings.Message | Should -Match "No process data could be parsed successfully."
        }

        It "Correctly parses various process lines (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $output = & $PathToRun -Format json -ErrorAction Stop
            $jsonOutput = $output | ConvertFrom-Json

            $targetProc = $jsonOutput | Where-Object {$_.PID -eq 1}
            $targetProc | Should -Not -BeNull
            $targetProc.Name | Should -Be 'launchd'
            $targetProc.User | Should -Be 'root'
            $targetProc.CPU_Percent | Should -Be 0.2
            $targetProc.Memory_MB | Should -Be ([math]::Round(20480 / 1024, 2)) 
        }

        It "Verifies that mock for 'ps' command was called (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            & $PathToRun -ErrorAction SilentlyContinue
            Assert-MockCalled -CommandName ps -Exactly 1 -Scope It 
        }
    }
}
