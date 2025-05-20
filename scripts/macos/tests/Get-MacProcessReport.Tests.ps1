# Get-MacProcessReport.Tests.ps1

# $PSScriptRoot is the directory of this test file.
Write-Host "DEBUG_TOP: PSScriptRoot at top level is '$PSScriptRoot'"
# We'll define the actual $PathToScript inside BeforeAll using its $PSScriptRoot

Describe "Get-MacProcessReport.ps1 - macOS Process Reporter" -Tags 'macOS', 'ProcessReport' {

    # Mock data (remains the same)
    $mockPsOutput_Header = "USER               PID %CPU   RSS COMM"
    # ... (rest of mock data) ...
    $mockPsOutput_Data = @(
        "jdoe              1234  5.5 51200 SomeApp",      
        "root                 1  0.2 20480 launchd",      
        "jdoe              5678 12.1 102400 pwsh",        
        "_mdnsresponder   234  0.0  8192 mDNSResponder" 
    )
    $mockPsOutput_Full = @($mockPsOutput_Header) + $mockPsOutput_Data


    # These will be populated within BeforeAll
    $script:ResolvedScriptPath = $null
    $script:TempTestDir = $null

    BeforeAll {
        Write-Host "DEBUG_BeforeAll: PSScriptRoot inside BeforeAll is '$PSScriptRoot'"

        if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            Write-Error "FATAL_BeforeAll: \$PSScriptRoot is NULL or EMPTY inside BeforeAll. Cannot determine test script's own path."
            throw "FATAL_BeforeAll: \$PSScriptRoot is empty in BeforeAll."
        }

        # Calculate $PathToScriptToTest INSIDE BeforeAll using its $PSScriptRoot
        $PathToScriptToTest = Join-Path $PSScriptRoot "..\Get-MacProcessReport.ps1"
        Write-Host "DEBUG_BeforeAll: Path to script under test calculated as: '$PathToScriptToTest'"

        if ([string]::IsNullOrWhiteSpace($PathToScriptToTest)) {
             Write-Error "FATAL_BeforeAll: Calculated PathToScriptToTest is NULL or EMPTY."
             throw "FATAL_BeforeAll: PathToScriptToTest is empty after Join-Path."
        }
        
        try {
            $script:ResolvedScriptPath = (Resolve-Path $PathToScriptToTest -ErrorAction Stop).Path
            Write-Host "INFO: Testing script at '$($script:ResolvedScriptPath)'"
        }
        catch {
            Write-Error "FATAL_BeforeAll: Could not find/resolve the script to test at '$PathToScriptToTest'. Error: $($_.Exception.Message)"
            throw # Stop tests if script is not found
        }

        # Create a temporary directory for file output tests
        try {
            $script:TempTestDir = Join-Path $env:TEMP "PesterMacProcessReporter_$(Get-Random)"
            New-Item -ItemType Directory -Path $script:TempTestDir -Force -ErrorAction Stop | Out-Null
            Write-Host "INFO: Temp directory created at '$($script:TempTestDir)'"
        }
        catch {
            Write-Error "FATAL_BeforeAll: Failed to create temp directory at '$($script:TempTestDir)'. Error: $($_.Exception.Message)"
            throw
        }
    }

    AfterAll {
        # Clean up the temporary directory
        if ($script:TempTestDir -and (Test-Path $script:TempTestDir -PathType Container)) {
            Write-Host "INFO: Cleaning up temp directory '$($script:TempTestDir)'"
            Remove-Item $script:TempTestDir -Recurse -Force
        }
    }

    BeforeEach {
        # Mock the 'ps' command before each test.
        Mock ps {
            return $mockPsOutput_Full
        } -ModuleName Get-MacProcessReport # Or just use -CommandName 'ps' if ModuleName is tricky
                                          # If Get-MacProcessReport.ps1 is not a module, Pester might
                                          # have trouble with -ModuleName. -CommandName 'ps' is more general.
                                          # Let's try with -CommandName for broader compatibility first.
        # Mock ps { return $mockPsOutput_Full } -CommandName 'ps'
    }

    # ... (Rest of your Context and It blocks should be fine if BeforeAll passes) ...
    Context "Default Behavior (CSV to Console)" {
        It "Should output CSV data to the console" {
            $output = & $script:ResolvedScriptPath -ErrorAction Stop
            $csvData = $output | ConvertFrom-Csv

            $csvData.Count | Should -Be $mockPsOutput_Data.Count 

            $csvData[0].PID | Should -Be '5678' 
            $csvData[0].Name | Should -Be 'pwsh'
            $csvData[0].CPU_Percent | Should -Be '12.1'
            $csvData[0].Memory_MB | Should -Be ([math]::Round(102400 / 1024, 2)).ToString() 
        }
    }

    Context "JSON Output" {
        It "Should output JSON data to the console when -Format json is specified" {
            $output = & $script:ResolvedScriptPath -Format json -ErrorAction Stop
            $jsonData = $output | ConvertFrom-Json

            $jsonData.Count | Should -Be $mockPsOutput_Data.Count

            $jsonData[0].PID | Should -Be 5678 
            $jsonData[0].CPU_Percent | Should -Be 12.1
            $jsonData[0].Memory_MB | Should -Be ([math]::Round(102400 / 1024, 2)) 
        }
    }

    Context "File Output" {
        It "Should save a CSV report to the specified -OutputPath" {
            $testCsvPath = Join-Path $script:TempTestDir "mac_processes_test.csv"
            & $script:ResolvedScriptPath -OutputPath $testCsvPath -ErrorAction Stop

            Test-Path $testCsvPath -PathType Leaf | Should -Be $true
            $fileContent = Get-Content $testCsvPath | ConvertFrom-Csv
            $fileContent.Count | Should -Be $mockPsOutput_Data.Count
            $fileContent[0].PID | Should -Be '5678' 
        }

        It "Should save a JSON report to the specified -OutputPath when -Format json is specified" {
            $testJsonPath = Join-Path $script:TempTestDir "mac_processes_test.json"
            & $script:ResolvedScriptPath -Format json -OutputPath $testJsonPath -ErrorAction Stop

            Test-Path $testJsonPath -PathType Leaf | Should -Be $true
            $fileContent = Get-Content $testJsonPath | ConvertFrom-Json
            $fileContent.Count | Should -Be $mockPsOutput_Data.Count
            $fileContent[0].PID | Should -Be 5678 
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Should output a warning if 'ps' command returns no process data lines" {
            Mock ps { return $mockPsOutput_Header } -CommandName 'ps' # Using -CommandName
            
            $WarningOutput = Invoke-Command {
                $WarningPreference = 'Continue' 
                & $script:ResolvedScriptPath -ErrorAction SilentlyContinue 
            } -WarningVariable ScriptWarnings -ErrorAction SilentlyContinue
            
            $ScriptWarnings.Message | Should -Contain "No process data could be parsed successfully."
        }

         It "Should output a warning for unparseable lines from 'ps'" {
            $malformedLine = "this is not a valid process line"
            $customMockPsOutput = @($mockPsOutput_Header, $mockPsOutput_Data[0], $malformedLine, $mockPsOutput_Data[1])
            Mock ps { return $customMockPsOutput } -CommandName 'ps' # Using -CommandName
            
            $WarningOutput = Invoke-Command {
                $WarningPreference = 'Continue'
                & $script:ResolvedScriptPath -ErrorAction SilentlyContinue
            } -WarningVariable ScriptWarnings -ErrorAction SilentlyContinue
            
            $ScriptWarnings.Message | Should -Contain "Could not parse process line: '$malformedLine'"
            $output = & $script:ResolvedScriptPath; $csvOutput = $output | ConvertFrom-Csv
            $csvOutput.Count | Should -Be 2 
        }
    }
}
