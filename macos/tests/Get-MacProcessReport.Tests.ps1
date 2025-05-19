# macos/tests/Get-MacProcessReport.Tests.ps1

$ScriptPath = Join-Path $PSScriptRoot "..\Get-MacProcessReport.ps1" # Path to the macOS script

Describe "Get-MacProcessReport.ps1 (macOS)" -Tags 'ProcessReport', 'macOS' {

    $script:SharedData = $null # Will be initialized in BeforeAll

    BeforeAll {
        $script:SharedData = @{
            ScriptPathToTest = $null
            TempDir          = $null
        }
        try {
            $script:SharedData.ScriptPathToTest = (Resolve-Path $ScriptPath -ErrorAction Stop).Path
        } catch { Write-Error "FATAL: Could not resolve Mac script path '$ScriptPath'. Error: $($_.Exception.Message)"; throw }

        if (-not (Test-Path $script:SharedData.ScriptPathToTest -PathType Leaf)) {
            Write-Error "FATAL: Mac script to test not found at '$($script:SharedData.ScriptPathToTest)'"
            throw
        }
        Write-Host "BeforeAll (macOS): ScriptPathToTest = '$($script:SharedData.ScriptPathToTest)'"

        $script:SharedData.TempDir = Join-Path $env:TEMP "MacProcessReporterTests_$(Get-Random)"
        if (-not (Test-Path $script:SharedData.TempDir -PathType Container)) {
            New-Item -ItemType Directory -Path $script:SharedData.TempDir -Force -ErrorAction Stop | Out-Null
        }
        Write-Host "BeforeAll (macOS): TempDir = '$($script:SharedData.TempDir)'"
    }

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
            # Mock the 'ps' command.
            # Since 'ps' is an external executable, Pester's 'Mock' command might not intercept it directly
            # in all PowerShell versions or environments when called simply as 'ps'.
            # A more robust way to mock external commands is to put them in the path or use an alias.
            # For simplicity here, we assume 'Mock ps' works or that the script uses Invoke-Command/Start-Process.
            # If Get-MacProcessReport.ps1 calls 'ps' directly, this basic Mock should work.
            Mock ps {
                param($ArgumentList) # Capture arguments if needed for more complex mocks
                # For this test, always return the same mock output
                Write-Verbose "Mock 'ps' called with args: $ArgumentList"
                return $mockPsOutput_Full
            } -Verifiable
        }

        It "Generates CSV output to console by default (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $output = & $PathToRun -ErrorAction Stop
            $csvOutput = $output | ConvertFrom-Csv

            $csvOutput.Count | Should -Be $mockPsOutput_Data.Count
            $firstDataProc = $mockPsOutput_Data[1] # jdoe 5678 (pwsh, highest CPU in mock after sort)
            $parsedFirstDataProc = $firstDataProc -match '^\s*(?<user>\S+)\s+(?<pid>\d+)\s+(?<cpu>[\d\.]+)\s+(?<rss>\d+)\s+(?<name>.+)$'
            
            # Script sorts by CPU desc. 'pwsh' has 12.1
            $csvOutput[0].PID | Should -Be '5678'
            $csvOutput[0].Name | Should -Be 'pwsh'
            $csvOutput[0].User | Should -Be 'jdoe'
            $csvOutput[0].CPU_Percent | Should -Be '12.1'
            $csvOutput[0].Memory_MB | Should -Be ([math]::Round(102400 / 1024, 2)).ToString() # 100.00
        }

        It "Generates JSON output to console when -Format json is specified (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $output = & $PathToRun -Format json -ErrorAction Stop
            $jsonOutput = $output | ConvertFrom-Json

            $jsonOutput.Count | Should -Be $mockPsOutput_Data.Count
            $jsonOutput[0].PID | Should -Be 5678 # pwsh
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
            $fileContent[0].PID | Should -Be '5678' # pwsh
        }
        
        It "Handles empty or minimal 'ps' output (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            Mock ps { return @($mockPsOutput_Header) } # Only header, no data
            
            $WarningOutput = Invoke-Command {
                $WarningPreference = 'Continue'
                & $PathToRun -ErrorAction SilentlyContinue
            } -WarningVariable ScriptWarnings -ErrorAction SilentlyContinue

            # Script should produce an empty report or a warning
            $ScriptWarnings.Message | Should -Match "No process data could be parsed successfully."
            # Or, if it outputs an empty CSV/JSON, check that
            # $output = & $PathToRun; $output.Length | Should -BeLessThan 2 # e.g. only header for CSV
        }

        It "Correctly parses various process lines (macOS)" {
            # This test focuses on the parsing logic within the script for different ps lines
            # For this, we might not call the full script, but invoke its parsing part, or rely on full runs.
            # Here, we'll check one of the mock lines through a full run.
            $PathToRun = $script:SharedData.ScriptPathToTest
            $output = & $PathToRun -Format json -ErrorAction Stop
            $jsonOutput = $output | ConvertFrom-Json

            $targetProc = $jsonOutput | Where-Object {$_.PID -eq 1}
            $targetProc | Should -Not -BeNull
            $targetProc.Name | Should -Be 'launchd'
            $targetProc.User | Should -Be 'root'
            $targetProc.CPU_Percent | Should -Be 0.2
            $targetProc.Memory_MB | Should -Be ([math]::Round(20480 / 1024, 2)) # 20.00
        }

        It "Verifies that mock for 'ps' command was called (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            & $PathToRun -ErrorAction SilentlyContinue
            Assert-MockCalled -CommandName ps -Exactly 1 -Scope It # ps should be called once
        }
    }
}