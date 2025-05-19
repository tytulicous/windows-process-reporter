# Windows Process Reporter CLI Tool

A robust PowerShell command-line tool to generate detailed reports of running processes on a Windows system. This utility provides insights into process activity, including Process ID (PID), Name, User, CPU Usage (%), and Memory Usage (MB), with flexible output options.

[![CI Pipeline](https://github.com/tytulicous/windows-process-reporter/actions/workflows/ci.yml/badge.svg)](https://github.com/tytulicous/windows-process-reporter/actions/workflows/ci.yml)

## Features

-   **Comprehensive Process Data:** Lists running processes with key metrics: PID, Name, User, CPU%, Memory (MB).
-   **Flexible Output:** Generates reports in CSV or JSON format.
-   **File or Console Output:** Save reports to a specified file or display directly in the console.
-   **Portable:** A single PowerShell script (`Get-ProcessReport.ps1`) with no external binary dependencies (requires PowerShell only).
-   **User-Friendly:** Clear command-line interface, verbose output options, and helpful error messages.
-   **Automated Testing:** Includes a suite of Pester tests for validating core functionality.
-   **Continuous Integration:** GitHub Actions workflow automatically tests the tool on code changes.

## Prerequisites

-   **Operating System:** Windows (tested on Windows 10/11, Windows Server 2016+).
-   **PowerShell:** Version 5.1 or higher (standard on modern Windows).
-   **Administrator Privileges (Recommended):** For full access to all process information (especially `User` for system processes and accurate `CPU %`), running the script with Administrator rights is highly recommended. Without elevation, some data might be "N/A" or incomplete.

## Installation

1.  **Download or Clone:**
    *   **Direct Download:** Download the `Get-ProcessReport.ps1` script. If you intend to run tests locally, also download the `tests` directory and its contents.
    *   **Git Clone:** For the complete project including tests and CI configuration:
        ```bash
        git clone https://github.com/tytulicous/windows-process-reporter.git
        cd windows-process-reporter
        ```

2.  **PowerShell Execution Policy:**
    By default, PowerShell's execution policy might prevent running downloaded scripts. To run `Get-ProcessReport.ps1`:
    *   **For the current session only (recommended for quick use):**
        Open PowerShell and run:
        ```powershell
        Set-ExecutionPolicy Bypass -Scope Process -Force
        ```
    *   **When calling from `cmd.exe` or a scheduler:**
        ```powershell
        powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\Get-ProcessReport.ps1" [parameters]
        ```
    *   **More permanent changes (requires Administrator privileges):**
        ```powershell
        # Allows running local scripts and signed remote scripts
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        ```
        *(Understand the security implications before changing execution policies system-wide.)*

## Usage

Navigate to the directory containing `Get-ProcessReport.ps1` in a PowerShell terminal (run as Administrator for best results).

**Basic Syntax:**

```powershell
.\Get-ProcessReport.ps1 [-Format <csv|json>] [-OutputPath <FilePath>] [-Verbose]
Use code with caution.
Markdown
Parameters:
Parameter	Type	Description	Default	Required
-Format	String	Output format for the report. Valid values: csv, json.	csv	No
-OutputPath	String	Full path to save the report file. If omitted, output is to the console.	Console	No
-Verbose	Switch	Enables detailed operational messages from the script. Useful for debugging.	N/A	No
Examples:
Generate a CSV report and display it in the console (default):
.\Get-ProcessReport.ps1
Use code with caution.
Powershell
Generate a JSON report and display it in the console:
.\Get-ProcessReport.ps1 -Format json
Use code with caution.
Powershell
Save a CSV report to a specific file:
.\Get-ProcessReport.ps1 -OutputPath "C:\Reports\ProcessAnalysis.csv"
Use code with caution.
Powershell
(Ensure the directory C:\Reports exists or the script has permissions to create it.)
Save a JSON report to a file in the current directory with verbose output:
.\Get-ProcessReport.ps1 -Format json -OutputPath ".\current_processes.json" -Verbose
Use code with caution.
Powershell
Run from any directory (if the script is in your PATH or using its full path):
C:\Scripts\Get-ProcessReport.ps1 -Format csv
Use code with caution.
Powershell
Output Format Details
CSV (Comma Separated Values):
A standard CSV file, easily importable into spreadsheet software.
Columns: PID, Name, User, CPU_Percent, Memory_MB
Example:
"PID","Name","User","CPU_Percent","Memory_MB"
"4128","chrome","MYLAPTOP\User","12.5","350.22"
"1024","svchost","NT AUTHORITY\SYSTEM","0.8","65.10"
Use code with caution.
Csv
JSON (JavaScript Object Notation):
An array of process objects, suitable for programmatic parsing or use with various data tools.
Example:
[
  {
    "PID": 4128,
    "Name": "chrome",
    "User": "MYLAPTOP\\User",
    "CPU_Percent": 12.5,
    "Memory_MB": 350.22
  },
  {
    "PID": 1024,
    "Name": "svchost",
    "User": "NT AUTHORITY\\SYSTEM",
    "CPU_Percent": 0.8,
    "Memory_MB": 65.10
  }
]
Use code with caution.
Json
Data Visualization
The generated CSV or JSON reports can be visualized using various tools:
1. Spreadsheet Software (Excel, Google Sheets, LibreOffice Calc) - for CSV:
a. Generate a CSV report: .\Get-ProcessReport.ps1 -OutputPath "processes.csv"
b. Open processes.csv in your preferred spreadsheet application.
c. Example: Charting Total Processes Per User:
1. Create a PivotTable (Excel: Insert > PivotTable, Google Sheets: Data > Pivot table).
2. Set User as Rows.
3. Set PID (or Name) as Values, summarized by Count.
4. Insert a Bar Chart or Pie Chart based on the PivotTable data.
2. Programming Languages (e.g., Python with Pandas & Matplotlib) - for CSV/JSON:
This allows for more custom and advanced visualizations.
a. Generate the report: .\Get-ProcessReport.ps1 -Format json -OutputPath "processes.json"
b. Example Python script:
```python
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns # Optional, for nicer plots
# Load data (adjust for CSV if needed: pd.read_csv("processes.csv"))
  df = pd.read_json("processes.json")

  # Set a style (optional)
  sns.set_style("whitegrid")

  # Top 10 processes by Memory Usage
  top_memory = df.nlargest(10, 'Memory_MB')
  plt.figure(figsize=(10, 6))
  sns.barplot(x='Memory_MB', y='Name', data=top_memory, palette="viridis")
  plt.title('Top 10 Processes by Memory Usage (MB)')
  plt.xlabel('Memory Usage (MB)')
  plt.ylabel('Process Name')
  plt.tight_layout()
  plt.show()

  # CPU Usage Distribution (Histogram)
  plt.figure(figsize=(10, 6))
  sns.histplot(df['CPU_Percent'], kde=True, bins=20, color="skyblue")
  plt.title('Distribution of CPU Usage (%)')
  plt.xlabel('CPU Usage (%)')
  plt.ylabel('Number of Processes')
  plt.tight_layout()
  plt.show()
  ```
Automated Tests (Pester)
This project includes a suite of automated tests written using the Pester framework to ensure the reliability and correctness of Get-ProcessReport.ps1.
Running Tests Locally:
Ensure Pester is Installed: Pester is typically bundled with modern PowerShell, but to install/update (tests are compatible with Pester 5+):
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
Import-Module Pester
Use code with caution.
Powershell
Navigate to the Project Root: Open PowerShell in the directory where you cloned or downloaded the project.
Execute Pester:
Invoke-Pester -Path ./tests
Use code with caution.
Powershell
For more detailed output:
Invoke-Pester -Path ./tests -Output Detailed
Use code with caution.
Powershell
The tests reside in the ./tests directory and utilize mocking for system cmdlets (Get-Process, Get-WmiObject) to provide consistent and isolated test environments. They cover core functionalities like output generation, file saving, and edge case handling.
Troubleshooting
"Script cannot be loaded because running scripts is disabled...": Refer to the Execution Policy section.
User field shows "N/A" or errors for many processes: Run the script with Administrator privileges.
CPU_Percent is 0 or inaccurate: This can be due to permissions (run as Admin) or issues with Windows Performance Counters. The WMI class Win32_PerfFormattedData_PerfProc_Process is used.
"Failed to save report to...": Verify the output directory exists and you have write permissions. The script attempts to create the parent directory.
Pester Test Failures: Check the detailed error output from Invoke-Pester. Ensure mocks are correctly defined or that script changes haven't invalidated test assumptions.
Continuous Integration (CI)
This repository uses GitHub Actions for Continuous Integration. The workflow is defined in .github/workflows/ci.yml. On every push or pull request to the main branches, the CI pipeline automatically:
Checks out the latest code.
Sets up a Windows environment with PowerShell.
Installs the Pester testing framework.
Executes the Pester automated tests.
This ensures that new changes maintain the tool's functionality and don't introduce regressions. You can view the status of these checks via the "Actions" tab on the GitHub repository page.
Contributing
Contributions, issues, and feature requests are welcome! Please feel free to:
Open an issue to report bugs or suggest enhancements.
Fork the repository and submit a pull request with your changes.
(Please ensure Pester tests pass with your contributions.)
License
This project is open-source. MIT License
