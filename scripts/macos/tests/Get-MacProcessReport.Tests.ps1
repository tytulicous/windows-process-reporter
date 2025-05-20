# Get-MacProcessReport.Tests.ps1

# Determine the path to the script under test.
# $PSScriptRoot is the directory of this test file.
# The script Get-MacProcessReport.ps1 is expected to be one level up.
$PathToScript = Join-Path $PSScriptRoot "..\Get-MacProcessReport.ps1"

Describe "Get-MacProcessReport.ps1 - macOS Process Reporter" -Tags 'macOS', 'ProcessReport' {

    # Mock data for the 'ps' command output
    $mockPsOutput_Header = "USER               PID %CPU   RSS COMM"
    $mockPsOutput_Data = @(
        "jdoe              1234  5.5 51200 SomeApp",       # 50MB
        "root                 1  0.2 20480 launchd",       # 20MB
        "jdoe              5678 12.1 102400 pwsh",        # 100MB
        "_mdnsresponder   234  0.0  8192 mDNSResponder"  # 8MB
    )
    $mockPsOutput_Full = @($mockPsOutput_Header) + $mockPsOutput_Data

    # Shared temporary directory for tests that write files
    $script:TempTestDir = ''

    BeforeAll {
        # Resolve the path to the script to ensure it exists before tests run.
        try {
            $script:ResolvedScriptPath = (Resolve-Path $PathToScript -ErrorAction Stop).Path
            Write-Host "INFO: Testing script at '$($script:ResolvedScriptPath)'"
        }
        catch {
            Write-Error "FATAL: Could not find the script to test at expected location '$PathToScript'. Error: $($_.Exception.Message)"
            throw # Stop tests if script is not found
        }

        # Create a temporary directory for file output tests
        $script:TempTestDir = Join-Path $env:TEMP "PesterMacProcessReporter_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:TempTestDir -Force | Out-Null
    }

    AfterAll {
        # Clean up the temporary directory
        if (Test-Path $script:TempTestDir -PathType Container) {
            Remove-Item $script:TempTestDir -Recurse -Force
        }
    }

    BeforeEach {
        # Mock the 'ps' command before each test.
        # This ensures a consistent, predictable output for the script to process.
        Mock ps {
            # Parameters passed to 'ps' can be inspected via $ArgumentList if needed for more complex mocks
            # For these tests, we always return the same mock output.
            return $mockPsOutput_Full
        } -ModuleName Get-MacProcessReport # Important for mocking external commands called by a specific script
    }

    Context "Default Behavior (CSV to Console)" {
        It "Should output CSV data to the console" {
            $output = & $script:ResolvedScriptPath -ErrorAction Stop
            $csvData = $output | ConvertFrom-Csv

            $csvData.Count | Should -Be $mockPsOutput_Data.Count # Number of data rows

            # Script sorts by CPU (desc), then Memory (desc)
            # 1. jdoe 5678 12.1 102400 pwsh (100MB)
            # 2. jdoe 1234  5.5 51200 SomeApp (50MB)
            # 3. root    1  0.2 20480 launchd (20MB)
            # 4. _mdns   234  0.0  8192 mDNSResponder (8MB)

            $csvData[0].PID | Should -Be '5678' # pwsh
            $csvData[0].Name | Should -Be 'pwsh'
            $csvData[0].CPU_Percent | Should -Be '12.1'
            $csvData[0].Memory_MB | Should -Be ([math]::Round(102400 / 1024, 2)).ToString() # 100.00
        }
    }

    Context "JSON Output" {
        It "Should output JSON data to the console when -Format json is specified" {
            $output = & $script:ResolvedScriptPath -Format json -ErrorAction Stop
            $jsonData = $output | ConvertFrom-Json

            $jsonData.Count | Should -Be $mockPsOutput_Data.Count

            $jsonData[0].PID | Should -Be 5678 # pwsh (PowerShell converts to [int] for JSON numbers)
            $jsonData[0].CPU_Percent | Should -Be 12.1
            $jsonData[0].Memory_MB | Should -Be ([math]::Round(102400 / 1024, 2)) # 100.00
        }
    }

    Context "File Output" {
        It "Should save a CSV report to the specified -OutputPath" {
            $testCsvPath = Join-Path $script:TempTestDir "mac_processes_test.csv"
            & $script:ResolvedScriptPath -OutputPath $testCsvPath -ErrorAction Stop

            Test-Path $testCsvPath -PathType Leaf | Should -Be $true
            $fileContent = Get-Content $testCsvPath | ConvertFrom-Csv
            $fileContent.Count | Should -Be $mockPsOutput_Data.Count
            $fileContent[0].PID | Should -Be '5678' # pwsh
        }

        It "Should save a JSON report to the specified -OutputPath when -Format json is specified" {
            $testJsonPath = Join-Path $script:TempTestDir "mac_processes_test.json"
            & $script:ResolvedScriptPath -Format json -OutputPath $testJsonPath -ErrorAction Stop

            Test-Path $testJsonPath -PathType Leaf | Should -Be $true
            $fileContent = Get-Content $testJsonPath | ConvertFrom-Json
            $fileContent.Count | Should -Be $mockPsOutput_Data.Count
            $fileContent[0].PID | Should -Be 5678 # pwsh
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Should output a warning if 'ps' command returns no process data lines" {
            Mock ps { return $mockPsOutput_Header } -ModuleName Get-MacProcessReport # Only header, no data
            
            $WarningOutput = Invoke-Command {
                # Capture warnings by temporarily changing preference
                $WarningPreference = 'Continue' 
                & $script:ResolvedScriptPath -ErrorAction SilentlyContinue # Allow script to run despite warnings
            } -WarningVariable ScriptWarnings -ErrorAction SilentlyContinue
            
            # Depending on script logic, it might produce an empty report or a specific warning.
            # Your script outputs "No process data could be parsed successfully."
            $ScriptWarnings.Message | Should -Contain "No process data could be parsed successfully."
        }

         It "Should output a warning for unparseable lines from 'ps'" {
            $malformedLine = "this is not a valid process line"
            $customMockPsOutput = @($mockPsOutput_Header, $mockPsOutput_Data[0], $malformedLine, $mockPsOutput_Data[1])
            Mock ps { return $customMockPsOutput } -ModuleName Get-MacProcessReport
            
            $WarningOutput = Invoke-Command {
                $WarningPreference = 'Continue'
                & $script:ResolvedScriptPath -ErrorAction SilentlyContinue
            } -WarningVariable ScriptWarnings -ErrorAction SilentlyContinue
            
            $ScriptWarnings.Message | Should -Contain "Could not parse process line: '$malformedLine'"
            # Also check that valid lines were still processed
            $output = & $script:ResolvedScriptPath; $csvOutput = $output | ConvertFrom-Csv
            $csvOutput.Count | Should -Be 2 # Only the two valid lines should be in the report
        }
    }
}
