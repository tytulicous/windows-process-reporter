# Multi-Platform Process Reporter CLI Tool

A robust command-line tool to generate detailed reports of running processes on both **Windows** and **macOS** systems. This utility provides insights into process activity, including Process ID (PID), Name, User, CPU Usage (%), and Memory Usage (MB), with flexible output options. Ansible playbooks are provided for automated deployment.

[![CI Pipeline](https://github.com/tytulicous/windows-process-reporter/actions/workflows/ci.yml/badge.svg)](https://github.com/tytulicous/windows-process-reporter/actions/workflows/ci.yml)

## Features

-   **Cross-Platform Support:** Dedicated scripts for Windows and macOS.
-   **Comprehensive Process Data:** Lists running processes with key metrics: PID, Name, User, CPU%, Memory (MB).
-   **Flexible Output:** Generates reports in CSV or JSON format.
-   **File or Console Output:** Save reports to a specified file or display directly in the console.
-   **Portable Scripts:** Single PowerShell scripts (`.ps1`) for each platform, requiring only PowerShell (Windows PowerShell 5.1+ for Windows, PowerShell Core 7+ for macOS).
-   **User-Friendly:** Clear command-line interface, verbose output options, and helpful error messages.
-   **Automated Testing:** Includes suites of Pester tests for validating core functionality on both platforms.
-   **Continuous Integration:** GitHub Actions workflow automatically tests both Windows and macOS versions on code changes.
-   **Ansible Deployment:** Playbooks and example configurations provided for automated deployment to fleets of Windows and macOS machines.

## Project Structure

The project is organized as follows:

-   `README.md`: This file.
-   `LICENSE`: Project license.
-   `.github/workflows/ci.yml`: GitHub Actions CI pipeline configuration.
-   `scripts/`: Contains the source code for the reporter scripts and their tests.
    -   `windows/`: Windows-specific script (`Get-ProcessReport.ps1`) and Pester tests (`tests/`).
    -   `macos/`: macOS-specific script (`Get-MacProcessReport.ps1`) and Pester tests (`tests/`).
-   `ansible/`: Contains Ansible playbooks and files for deployment.
    -   `deploy_process_reporters.yml`: Main Ansible playbook for Windows & macOS.
    -   `inventory.ini.example`: Example Ansible inventory file.
    -   `files/`: Staging area for scripts to be deployed by Ansible.
        -   `windows/Get-ProcessReport.ps1`
        -   `macos/Get-MacProcessReport.ps1`
    -   `(Optional) promote_scripts_to_ansible.sh` or `Promote-ScriptsToAnsible.ps1`: Helper scripts to copy updated scripts from `scripts/` to `ansible/files/`.

---

## Windows Version (`scripts/windows/Get-ProcessReport.ps1`)

Generates a report of running processes on a Windows system.

### Prerequisites (Windows)

-   **Operating System:** Windows (Windows 10/11, Windows Server 2016+ recommended).
-   **PowerShell:** Version 5.1 or higher.
-   **Administrator Privileges (Recommended):** For full access to all process information.

### Usage (Windows)

1.  Open PowerShell (run as Administrator for best results).
2.  Navigate to the `scripts/windows/` directory.
3.  Execute:
    ```powershell
    .\Get-ProcessReport.ps1 [-Format <csv|json>] [-OutputPath <FilePath>] [-Verbose]
    ```

**Examples (Windows):**

-   CSV to console: `.\Get-ProcessReport.ps1`
-   JSON to file: `.\Get-ProcessReport.ps1 -Format json -OutputPath "C:\Reports\WinProcesses.json"`

*(Refer to the script's internal help for more details: `Get-Help .\Get-ProcessReport.ps1 -Full`)*

---

## macOS Version (`scripts/macos/Get-MacProcessReport.ps1`)

Generates a report of running processes on a macOS system using the native `ps` command.

### Prerequisites (macOS)

-   **Operating System:** macOS.
-   **PowerShell Core (`pwsh`):** Version 7.x or higher.
    -   Install: [Installing PowerShell on macOS](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-macos)
-   **Permissions:** For full process visibility, running with `sudo` might be necessary (e.g., `sudo pwsh ./Get-MacProcessReport.ps1`).

### Usage (macOS)

1.  Open your terminal (e.g., Terminal.app, iTerm2).
2.  Navigate to the `scripts/macos/` directory.
3.  Execute using `pwsh`:
    ```powershell
    pwsh ./Get-MacProcessReport.ps1 [-Format <csv|json>] [-OutputPath <FilePath>] [-Verbose]
    ```

**Examples (macOS):**

-   CSV to console: `pwsh ./Get-MacProcessReport.ps1`
-   JSON to file: `pwsh ./Get-MacProcessReport.ps1 -Format json -OutputPath "/Users/youruser/Documents/MacProcesses.json"`

*(Refer to the script's internal help: `Get-Help ./Get-MacProcessReport.ps1 -Full` inside a `pwsh` session)*

---

## Automated Tests (Pester)

Both Windows and macOS versions include Pester test suites to ensure reliability.

**Running Tests Locally:**

1.  **Ensure Pester is Installed:**
    For Windows PowerShell:
    ```powershell
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
    Import-Module Pester
    ```
    For PowerShell Core (`pwsh`) on macOS (or Windows/Linux):
    ```powershell
    pwsh -Command "Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser; Import-Module Pester"
    ```
2.  **Navigate to the Project Root** (`ProcessReporter/`).
3.  **Execute Pester for the desired platform:**
    -   **Windows Tests:**
        ```powershell
        Invoke-Pester -Path ./scripts/windows/tests
        ```
    -   **macOS Tests (using `pwsh`):**
        ```powershell
        pwsh -Command "Invoke-Pester -Path ./scripts/macos/tests"
        ```
    For more detailed output, add `-Output Detailed` to the `Invoke-Pester` command.

---

## Ansible Deployment

This project includes Ansible playbooks for automated deployment of the Process Reporter scripts to fleets of Windows and macOS machines. The Ansible artifacts are located in the `ansible/` directory.

### Prerequisites for Ansible Deployment

-   **Ansible Control Node:** A Linux machine with Ansible installed.
-   **Target Hosts:**
    -   **Windows:** Configured for WinRM. The `ansible_user` must have administrative privileges.
    -   **macOS:** Configured for SSH (key-based authentication recommended). PowerShell Core (`pwsh`) must be installed. The `ansible_user` should have `sudo` capabilities if elevated privileges are needed for script execution or directory creation (e.g., for `become: yes` in the playbook).
-   **Inventory File:** Create an `inventory.ini` file within the `ansible/` directory (or point to your existing inventory) based on `ansible/inventory.ini.example`. **Do not commit your actual inventory with sensitive credentials to Git.** Use Ansible Vault for secrets.
-   **Deployment Scripts:** The scripts that Ansible deploys are expected to be in `ansible/files/windows/` and `ansible/files/macos/`.

### Staging Scripts for Ansible Deployment

The Ansible playbook deploys scripts from the `ansible/files/` directory. The source scripts are developed and tested in the `scripts/` directory. To update the scripts Ansible deploys:

1.  Modify and test your scripts in `scripts/windows/` or `scripts/macos/`.
2.  Commit changes to the source scripts.
3.  **Copy the updated script(s) from `scripts/...` to the corresponding `ansible/files/...` location.**
    -   Example: `cp ./scripts/windows/Get-ProcessReport.ps1 ./ansible/files/windows/`
    -   Helper scripts (`promote_scripts_to_ansible.sh` or `Promote-ScriptsToAnsible.ps1`) might be provided in the `ansible/` directory or project root for convenience.
4.  Stage and commit these updated deployment files in `ansible/files/` to your Git repository.

### Running the Ansible Playbook

1.  Navigate to the `ansible/` directory on your Ansible control node (or ensure your `ansible.cfg` is set up).
2.  Execute the playbook:
    ```bash
    ansible-playbook deploy_process_reporters.yml -i inventory.ini
    ```
    If using Ansible Vault for encrypted variables (recommended for passwords):
    ```bash
    ansible-playbook deploy_process_reporters.yml -i inventory.ini --ask-vault-pass
    ```

The playbook will:
-   Connect to hosts defined in your inventory.
-   Create necessary directories on target machines.
-   Copy the appropriate platform-specific script from `ansible/files/` to the target.
-   Execute the script on the target.
-   Fetch the generated report (CSV by default) back to a `collected_reports/[hostname]/` directory on the Ansible control node.

Refer to `ansible/deploy_process_reporters.yml` and `ansible/inventory.ini.example` for detailed configuration.

---

## Output Formats & Visualization

Both scripts support CSV and JSON output formats. These can be visualized using:
-   Spreadsheet software (Excel, Google Sheets, LibreOffice Calc) for CSV.
-   Programming languages (e.g., Python with Pandas & Matplotlib) for CSV/JSON.
*(See earlier sections in this README for more detailed visualization examples, adapting paths as needed.)*

## Troubleshooting

-   **Script Execution Issues (Windows/macOS):**
    -   Ensure correct PowerShell version is installed.
    -   Check PowerShell Execution Policy (Windows).
    -   Run with Administrator/`sudo` privileges for complete data.
    -   Verify script paths and output paths.
-   **Pester Test Failures:** Examine `Invoke-Pester` output. Ensure mocks are correct and test assumptions align with script logic.
-   **Ansible Deployment Issues:**
    -   Verify WinRM/SSH connectivity to targets.
    -   Check `ansible_user` permissions on targets.
    -   Ensure `pwsh` is in PATH on macOS targets for Ansible modules and script execution.
    -   Consult Ansible playbook output for detailed error messages.

## Continuous Integration (CI)

This repository uses GitHub Actions for CI (see `.github/workflows/ci.yml`). The pipeline automatically:
1.  Checks out code.
2.  Sets up Windows and macOS environments with appropriate PowerShell versions.
3.  Installs Pester.
4.  **Executes Pester tests for both Windows and macOS scripts** from their respective `scripts/[platform]/tests` directories.

## Contributing

Contributions, issues, and feature requests are welcome!
1.  Fork the repository.
2.  Create your feature branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Ensure all Pester tests pass for both platforms.
5.  Push to the branch (`git push origin feature/AmazingFeature`).
6.  Open a Pull Request.

## License

Distributed under the MIT License. See `LICENSE` file for more information.
