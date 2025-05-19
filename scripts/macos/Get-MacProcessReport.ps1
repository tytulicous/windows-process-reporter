<#
.SYNOPSIS
    Generates a comprehensive report of running processes on a macOS system.
.DESCRIPTION
    This CLI tool lists running processes on macOS, including details such as process ID (PID), name,
    user, CPU usage percentage, and memory usage (Resident Set Size in MB).
    The report can be output in CSV or JSON format.
.PARAMETER Format
    Specifies the output format for the report.
    Valid values are 'csv' or 'json'. Default is 'csv'.
.PARAMETER OutputPath
    Specifies the full path to the file where the report will be saved.
    If not specified, the report is output to the console.
.EXAMPLE
    pwsh ./Get-MacProcessReport.ps1
    # Generates a CSV report to the console on macOS.

.EXAMPLE
    pwsh ./Get-MacProcessReport.ps1 -Format json
    # Generates a JSON report to the console on macOS.

.EXAMPLE
    pwsh ./Get-MacProcessReport.ps1 -OutputPath "/Users/youruser/Reports/ProcessReport.csv"
    # Generates a CSV report and saves it.

.NOTES
    Author: Your Name/AI Assistant
    Version: 1.0
    Requires: PowerShell Core (pwsh) 7.x or higher on macOS.
    The 'ps' command is used internally.
    CPU % is often an average over a short period.
    Memory (RSS) is Resident Set Size.
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory = $false, HelpMessage = "Output format: 'csv' or 'json'. Default is 'csv'.")]
    [ValidateSet('csv', 'json')]
    [string]$Format = 'csv',

    [Parameter(Mandatory = $false, HelpMessage = "Full path to save the report file. Outputs to console if not specified.")]
    [string]$OutputPath
)

try {
    Write-Verbose "Starting macOS process report generation."
    Write-Verbose "Selected format: $Format"
    if ($OutputPath) {
        Write-Verbose "Output path: $OutputPath"
    } else {
        Write-Verbose "Outputting to console."
    }

    # Using 'ps -axcro user,pid,%cpu,%mem,rss,comm'
    # -a : show processes of all users
    # -x : show processes not attached to a terminal
    # -c : show 'comm' (command name) instead of full command line for 'COMMAND' column
    # -r : sort by CPU usage (descending) - optional, can also sort in PowerShell
    # -o : specify output format columns
    # user: User name
    # pid: Process ID
    # %cpu: CPU usage percentage
    # %mem: Memory usage percentage (less precise than RSS for absolute values)
    # rss: Resident Set Size in Kilobytes
    # comm: Command name (often more succinct than 'command')

    # Execute ps command. Output is an array of strings. First line is header.
    # We need to handle potential errors from 'ps' itself, though it's usually stable.
    try {
        $psOutput = ps -axcro user,pid,%cpu,rss,comm -w -w # -w -w for wide output to prevent truncation if needed
        if ($null -eq $psOutput -or $psOutput.Count -lt 2) { # Expect header + at least one process
            Write-Warning "No process information could be gathered from 'ps' command or 'ps' output was empty."
            exit 1
        }
    }
    catch {
        Write-Error "Failed to execute 'ps' command. Error: $($_.Exception.Message)"
        exit 1
    }


    $report = @()
    # Skip the header line from psOutput
    foreach ($line in $psOutput | Select-Object -Skip 1) {
        # Trim leading/trailing whitespace from the line
        $trimmedLine = $line.Trim()

        # Regex to parse the line. Columns are space-separated.
        # USER PID %CPU RSS COMMAND
        # Example line: "jdoe     1234  0.5 12345 /Applications/AppName.app/Contents/MacOS/AppName"
        # Or more simply with 'comm': "jdoe     1234  0.5 12345 AppName"
        # The regex needs to be robust for varying whitespace.
        # Using a simpler split based on the known number of columns if output is regular
        # Or a more robust regex:
        # Columns: USER, PID, %CPU, RSS, COMMAND
        # ^\s*(?<user>\S+)\s+(?<pid>\d+)\s+(?<cpu>[\d\.]+)\s+(?<rss>\d+)\s+(?<name>.+)$
        if ($trimmedLine -match '^\s*(?<user>\S+)\s+(?<pid>\d+)\s+(?<cpu>[\d\.]+)\s+(?<rss>\d+)\s+(?<name>.+)$') {
            $processEntry = [PSCustomObject]@{
                PID         = [int]$Matches.pid
                Name        = $Matches.name.Trim() # Trim command name
                User        = $Matches.user
                CPU_Percent = [double]$Matches.cpu
                Memory_MB   = [math]::Round(([double]$Matches.rss) / 1024, 2) # RSS is in Kilobytes
            }
            $report += $processEntry
        } else {
            Write-Warning "Could not parse process line: '$trimmedLine'"
        }
    }

    if ($report.Count -eq 0) {
        Write-Warning "No process data could be parsed successfully."
        # Don't exit here if 'ps' ran but parsing failed for all; an empty report might be valid if truly no processes matched
    }

    # Sort by CPU descending, then by Memory descending as a secondary sort
    $report = $report | Sort-Object -Property CPU_Percent, Memory_MB -Descending


    # Output generation
    $outputData = ""
    if ($Format -eq 'csv') {
        $outputData = $report | ConvertTo-Csv -NoTypeInformation
    }
    elseif ($Format -eq 'json') {
        $outputData = $report | ConvertTo-Json -Depth 3
    }
    else {
        # Should not happen due to ValidateSet
        Write-Error "Invalid format specified: $Format. Choose 'csv' or 'json'."
        exit 1
    }

    if ($OutputPath) {
        if ($PSCmdlet.ShouldProcess($OutputPath, "Save Report File")) {
            try {
                $ParentDirectory = Split-Path -Path $OutputPath -Parent
                if ($ParentDirectory -and (-not (Test-Path -Path $ParentDirectory -PathType Container))) {
                    Write-Verbose "Creating directory: $ParentDirectory"
                    New-Item -ItemType Directory -Path $ParentDirectory -Force -ErrorAction Stop | Out-Null
                }
                Set-Content -Path $OutputPath -Value $outputData -Encoding UTF8 -ErrorAction Stop
                Write-Host "Report successfully saved to: $OutputPath" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to save report to '$OutputPath'. Error: $($_.Exception.Message)"
                exit 1
            }
        }
    }
    else {
        Write-Output $outputData
    }

    Write-Verbose "macOS process report generation finished."
}
catch {
    Write-Error "An unexpected error occurred: $($_.Exception.Message)"
    Write-Error "ScriptStackTrace: $($_.ScriptStackTrace)"
    exit 1
}