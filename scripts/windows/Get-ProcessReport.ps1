<#
.SYNOPSIS
    Generates a comprehensive report of running processes on a Windows system.
.DESCRIPTION
    This CLI tool lists running processes, including details such as process ID (PID), name,
    user, CPU usage percentage, and memory usage (Working Set in MB).
    The report can be output in CSV or JSON format, either to the console or to a specified file.
    For full user information for all processes, this script may need to be run with Administrator privileges.
.PARAMETER Format
    Specifies the output format for the report.
    Valid values are 'csv' or 'json'. Default is 'csv'.
.PARAMETER OutputPath
    Specifies the full path to the file where the report will be saved.
    If not specified, the report is output to the console.
.EXAMPLE
    .\Get-ProcessReport.ps1
    # Generates a CSV report to the console.

.EXAMPLE
    .\Get-ProcessReport.ps1 -Format json
    # Generates a JSON report to the console.

.EXAMPLE
    .\Get-ProcessReport.ps1 -OutputPath "C:\Reports\ProcessReport.csv"
    # Generates a CSV report and saves it to C:\Reports\ProcessReport.csv.

.EXAMPLE
    .\Get-ProcessReport.ps1 -Format json -OutputPath "D:\Data\processes.json"
    # Generates a JSON report and saves it to D:\Data\processes.json.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\Get-ProcessReport.ps1" -Format csv -OutputPath "C:\Reports\MyProcesses.csv"
    # Example of running from cmd.exe or a scheduler, bypassing execution policy for this run.

.NOTES
    Author: Your Name/AI Assistant
    Version: 1.0
    Requires: PowerShell 5.1 or higher.
    For accurate CPU usage and full user details for all processes, running as Administrator is recommended.
    CPU Usage is a point-in-time snapshot.
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
    Write-Verbose "Starting process report generation."
    Write-Verbose "Selected format: $Format"
    if ($OutputPath) {
        Write-Verbose "Output path: $OutputPath"
    } else {
        Write-Verbose "Outputting to console."
    }

    # Gather process information
    # Get-Counter is more accurate for instantaneous CPU % than Get-Process.CPU (which is total CPU time)
    # We'll get process info first, then enrich with CPU from counters.

    Write-Host "Gathering process information... This might take a moment for CPU usage." -ForegroundColor Yellow

    # Get base process information including username
    # -IncludeUserName requires elevation for processes not owned by the current user
    $processesInfo = Get-Process -IncludeUserName -ErrorAction SilentlyContinue

    # Prepare a map for CPU usage from performance counters
    # Querying all instances of '% Processor Time' for the 'Process' counter set
    # This can be slow if there are many processes.
    $cpuCounters = Get-Counter '\Process(*)\% Processor Time' -ErrorAction SilentlyContinue
    $cpuUsageMap = @{}
    if ($cpuCounters) {
        # Group counters by InstanceName (which is processname#instance or just processname)
        # and then sum up their cooked values. Some processes (like svchost) have many instances.
        # However, Get-Counter for '% Processor Time' for Process(*)\ actually gives per PID if available.
        # The InstanceName format for Process counter is "ProcessName" or "ProcessName#InstanceNumber"
        # We need to map this back to PIDs.
        # A more reliable way is to iterate Get-Process and for each PID get its counter if available.
        # Or, get WMI Win32_PerfFormattedData_PerfProc_Process which links PID and PercentProcessorTime
        
        $wmiCpuData = Get-WmiObject -Class Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' }
        
        foreach ($entry in $wmiCpuData) {
            if ($entry.IDProcess -ne 0) { # PID 0 is System Idle Process
                 # PercentProcessorTime is per core, so divide by logical core count for overall %
                 # However, Task Manager usually shows total % across all cores. So we use the raw value.
                $cpuUsageMap[$entry.IDProcess] = $entry.PercentProcessorTime 
            }
        }
    } else {
        Write-Warning "Could not retrieve CPU performance counters. CPU Usage will be reported as 0 or based on Get-Process.CPU (total seconds)."
        # Fallback to Get-Process.CPU (total seconds) if Get-Counter fails. Not ideal but better than nothing.
        # This column would then need renaming to CPU_TotalSeconds
    }


    $report = @()
    foreach ($proc in $processesInfo) {
        $userName = $proc.UserName
        if ([string]::IsNullOrWhiteSpace($userName)) {
            # For system processes or when user info can't be retrieved without admin
            # Try to get owner via WMI as a fallback, though Get-Process -IncludeUserName is usually better
            try {
                $ownerInfo = Get-WmiObject -Query "SELECT * FROM Win32_Process WHERE ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
                if ($ownerInfo) {
                    $domain = $ownerInfo.GetOwner().Domain
                    $user = $ownerInfo.GetOwner().User
                    if ($user) {
                        $userName = if ($domain) { "$domain\$user" } else { $user }
                    } else {
                        $userName = "N/A (Elevated rights may be needed)"
                    }
                } else {
                     $userName = "N/A (Elevated rights may be needed)"
                }
            } catch {
                $userName = "N/A (Error retrieving owner)"
            }
        }

        # Get CPU usage from our map; default to 0 if not found (e.g., process just started/ended or counter issue)
        $cpuPercent = $cpuUsageMap[$proc.Id]
        if ($null -eq $cpuPercent) {
            $cpuPercent = 0 
        }

        $processEntry = [PSCustomObject]@{
            PID         = $proc.Id
            Name        = $proc.ProcessName
            User        = $userName
            CPU_Percent = $cpuPercent # This is the value from WMI Win32_PerfFormattedData_PerfProc_Process
            Memory_MB   = [math]::Round($proc.WorkingSet64 / 1MB, 2)
        }
        $report += $processEntry
    }

    # Filter out entries where User is still null or whitespace, or where PID is 0 (System Idle Process if it got through)
    $report = $report | Where-Object { $_.PID -ne 0 -and -not ([string]::IsNullOrWhiteSpace($_.User)) } | Sort-Object -Property CPU_Percent -Descending


    if ($report.Count -eq 0) {
        Write-Warning "No process information could be gathered. If not running as Administrator, try again with elevated privileges."
        exit 1
    }

    # Output generation
    $outputData = ""
    if ($Format -eq 'csv') {
        $outputData = $report | ConvertTo-Csv -NoTypeInformation
    }
    elseif ($Format -eq 'json') {
        $outputData = $report | ConvertTo-Json -Depth 3 # Depth 3 should be enough for this flat structure
    }
    else {
        Write-Error "Invalid format specified: $Format. Choose 'csv' or 'json'."
        exit 1 # Should not happen due to ValidateSet
    }

    if ($OutputPath) {
        if ($PSCmdlet.ShouldProcess($OutputPath, "Save Report File")) {
            try {
                # Ensure directory exists
                $ParentDirectory = Split-Path -Path $OutputPath -Parent
                if (-not (Test-Path -Path $ParentDirectory)) {
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

    Write-Verbose "Process report generation finished."

}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    Write-Error "ScriptStackTrace: $($_.ScriptStackTrace)"
    exit 1
}