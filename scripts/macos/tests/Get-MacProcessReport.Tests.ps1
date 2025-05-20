# macos/tests/Get-MacProcessReport.Tests.ps1

# These top-level definitions are now mostly for your own clarity or if you needed them
# OUTSIDE of Pester blocks. For use *inside* Pester blocks, we'll rely on the
# $PSScriptRoot available within those blocks.
Write-Host "DEBUG_TOP: PSScriptRoot at top level is '$PSScriptRoot'"
$script:TopLevelCalculatedScriptPath = Join-Path $PSScriptRoot "..\Get-MacProcessReport.ps1"
Write-Host "DEBUG_TOP: \$script:TopLevelCalculatedScriptPath is: '$($script:TopLevelCalculatedScriptPath)'"

Describe "Get-MacProcessReport.ps1 (macOS)" -Tags 'ProcessReport', 'macOS' {

    $script:SharedData = $null # Will be initialized in BeforeAll

    BeforeAll {
        Write-Host "DEBUG_BeforeAll: --- START BeforeAll ---"
        Write-Host "DEBUG_BeforeAll: \$PSScriptRoot value inside BeforeAll is: '$PSScriptRoot'"

        $script:SharedData = @{
            ScriptPathToTest = $null
            TempDir          = $null
        }

        if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            Write-Error "FATAL_BeforeAll: \$PSScriptRoot is NULL or EMPTY inside BeforeAll. Cannot determine script path."
            throw "FATAL_BeforeAll: Script path is indeterminable because \$PSScriptRoot inside BeforeAll is empty."
        }

        # Primary and most reliable method: Use $PSScriptRoot from within this block
        $ResolvedPathTarget = Join-Path $PSScriptRoot "..\Get-MacProcessReport.ps1"
        Write-Host "DEBUG_BeforeAll: Path calculated using \$PSScriptRoot from BeforeAll: '$ResolvedPathTarget'"

        if ([string]::IsNullOrWhiteSpace($ResolvedPathTarget)) {
             Write-Error "FATAL_BeforeAll: Join-Path with \$PSScriptRoot from BeforeAll resulted in an empty path: '$ResolvedPathTarget'."
             throw "FATAL_BeforeAll: Path calculation failed even with BeforeAll's \$PSScriptRoot."
        }

        Write-Host "DEBUG_BeforeAll: Using '$ResolvedPathTarget' for Resolve-Path."
        try {
            $script:SharedData.ScriptPathToTest = (Resolve-Path $ResolvedPathTarget -ErrorAction Stop).Path
        } catch {
            Write-Error "FATAL_BeforeAll: Could not resolve Mac script path '$ResolvedPathTarget'. Error: $($_.Exception.Message)"
            throw
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

    # ... (AfterAll and Context blocks can remain the same) ...
    # ... (All 'It' blocks can remain the same) ...
}
