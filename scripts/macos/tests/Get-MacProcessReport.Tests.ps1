# macos/tests/Get-MacProcessReport.Tests.ps1

Write-Host "DEBUG_TOP: PSScriptRoot at top level is '$PSScriptRoot'"
Write-Host "DEBUG_TOP: Current Directory at top level is '$(Get-Location)'"

# Define the target script path in the script scope
$script:ScriptPath = Join-Path $PSScriptRoot "..\Get-MacProcessReport.ps1"
Write-Host "DEBUG_TOP: \$script:ScriptPath has been SET TO: '$($script:ScriptPath)'"

# Create a backup/reference of this top-level value for debugging inside BeforeAll
$script:Original_ScriptPath_Value_FromTop = $script:ScriptPath
Write-Host "DEBUG_TOP: \$script:Original_ScriptPath_Value_FromTop is: '$($script:Original_ScriptPath_Value_FromTop)'"

Describe "Get-MacProcessReport.ps1 (macOS)" -Tags 'ProcessReport', 'macOS' {

    $script:SharedData = $null # Will be initialized in BeforeAll

    BeforeAll {
        Write-Host "DEBUG_BeforeAll: --- START BeforeAll ---"
        Write-Host "DEBUG_BeforeAll: \$PSScriptRoot value inside BeforeAll is: '$PSScriptRoot'"
        Write-Host "DEBUG_BeforeAll: Attempting to read \$script:ScriptPath inside BeforeAll: '$($script:ScriptPath)'"
        Write-Host "DEBUG_BeforeAll: Value of \$script:Original_ScriptPath_Value_FromTop inside BeforeAll: '$($script:Original_ScriptPath_Value_FromTop)'"

        $script:SharedData = @{
            ScriptPathToTest = $null
            TempDir          = $null
        }

        $ResolvedPathTarget = $script:ScriptPath # Primary attempt: use the script-scoped variable

        if ([string]::IsNullOrWhiteSpace($ResolvedPathTarget)) {
            Write-Warning "DEBUG_BeforeAll: \$script:ScriptPath was found to be NULL or EMPTY inside BeforeAll."
            Write-Warning "DEBUG_BeforeAll: The original top-level value (\$script:Original_ScriptPath_Value_FromTop) was: '$($script:Original_ScriptPath_Value_FromTop)'"

            Write-Warning "DEBUG_BeforeAll: Attempting fallback using \$PSScriptRoot from within BeforeAll ('$PSScriptRoot')."
            if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
                $ResolvedPathTarget = Join-Path $PSScriptRoot "..\Get-MacProcessReport.ps1"
                Write-Host "DEBUG_BeforeAll: Fallback: Path re-calculated inside BeforeAll is: '$ResolvedPathTarget'"
                if ([string]::IsNullOrWhiteSpace($ResolvedPathTarget)) {
                    Write-Error "FATAL_BeforeAll: Fallback path calculation using \$PSScriptRoot inside BeforeAll also resulted in an empty path."
                    throw "FATAL_BeforeAll: Fallback path calculation failed."
                }
            } else {
                Write-Error "FATAL_BeforeAll: \$PSScriptRoot is also NULL or EMPTY inside BeforeAll. Cannot determine script path."
                throw "FATAL_BeforeAll: Script path is indeterminable as both methods failed."
            }
        }

        Write-Host "DEBUG_BeforeAll: Using '$ResolvedPathTarget' for Resolve-Path."
        try {
            $script:SharedData.ScriptPathToTest = (Resolve-Path $ResolvedPathTarget -ErrorAction Stop).Path
        } catch {
            Write-Error "FATAL_BeforeAll: Could not resolve Mac script path '$ResolvedPathTarget'. Error: $($_.Exception.Message)"
            throw # Re-throw the original exception or a custom one
        }

        if (-not (Test-Path $script:SharedData.ScriptPathToTest -PathType Leaf)) {
            Write-Error "FATAL_BeforeAll: Mac script to test not found at '$($script:SharedData.ScriptPathToTest)'"
            throw
        }
        Write-Host "DEBUG_BeforeAll: ScriptPathToTest successfully resolved to: '$($script:SharedData.ScriptPathToTest)'"

        $script:SharedData.TempDir = Join-Path $env:TEMP "MacProcessReporterTests_$(Get-Random)"
        if (-not (Test-Path $script:SharedData.TempDir -PathType Container)) {
            New-Item -ItemType Directory -Path $script:SharedData.TempDir -Force -ErrorAction Stop | Out-Null
        }
        Write-Host "DEBUG_BeforeAll: TempDir created at: '$($script:SharedData.TempDir)'"
        Write-Host "DEBUG_BeforeAll: --- END BeforeAll ---"
    }

    # (AfterAll and Context blocks remain the same as your last fully posted version)
    AfterAll {
        if ($script:SharedData -and $script:SharedData.TempDir -and (Test-Path $script:SharedData.TempDir -PathType Container)) {
            Remove-Item $script:SharedData.TempDir -Recurse -Force
        }
    }

    Context "Core Functionality with Mocks (macOS)" {
        $mockPsOutput_Header = "USER               PID %CPU   RSS COMM" 
        $mockPsOutput_Data = @(
            "root                 1  0.2 20480 launchd",
            "jdoe              1234  5.5 512000 SomeApp",
            "jdoe              5678 12.1 102400 pwsh",
            "_mdnsresponder   234  0.0  8192 mDNSResponder",
            "anotheruser       901  0.8 30720 UserEventAgent" 
        )
        $mockPsOutput_Full = @($mockPsOutput_Header) + $mockPsOutput_Data

        BeforeEach {
            # IMPORTANT: Ensure $script:SharedData.ScriptPathToTest is used here
            $PathToRun = $script:SharedData.ScriptPathToTest 
            if ([string]::IsNullOrWhiteSpace($PathToRun)) {
                throw "FATAL_BeforeEach: \$script:SharedData.ScriptPathToTest is empty! This means BeforeAll did not set it correctly."
            }
            Mock ps {
                param($ArgumentList)
                Write-Verbose "Mock 'ps' called with args: $ArgumentList"
                return $mockPsOutput_Full
            } -Verifiable
        }

        # ... All 'It' blocks remain the same as your last version ...
        It "Generates CSV output to console by default (macOS)" {
            $PathToRun = $script:SharedData.ScriptPathToTest
            $output = & $PathToRun -ErrorAction Stop
            $csvOutput = $output | ConvertFrom-Csv

            $csvOutput.Count | Should -Be $mockPsOutput_Data.Count
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
