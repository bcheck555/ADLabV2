# SCVMM 2025 Manual Installation Guide

> **Derived from:** `ansible/roles/scvmm/tasks/main.yml`
> **Purpose:** Step-by-step reference for manually installing System Center Virtual Machine Manager (SCVMM) 2025 in a production environment.

---

## Prerequisites & Environment Requirements

Before beginning, ensure the following conditions are met:

| Requirement | Detail |
|---|---|
| **SQL Server** | Must be fully configured and accessible **before** starting SCVMM setup. The database server (DB01) must be reachable on port 1433. |
| **Nested Virtualization** | The SCVMM host (VMM01) requires nested virtualization enabled at the hypervisor level (e.g., set in Hyper-V VM settings or Terraform configuration). |
| **Domain Controller** | Active Directory must be available. The SCVMM host must be able to reach a DC for domain join and AD object creation. |
| **Software Packages Required** | `adksetup.exe` (ADK offline layout), `adkwinpesetup.exe` (WinPE add-on offline layout), `setup.exe` (SCVMM 2025 installer), `msodbcsql.msi` (ODBC Driver for SQL Server), `MsSqlCmdLnUtils.msi` (SQL Command Line Utilities / sqlcmd) |

> ⚠️ **Note:** Installers should be staged **locally** on the SCVMM host before running — do not install directly from a network share. The automation notes SMB hangs as a known issue when running installers over a mapped network drive.

---

## Stage 1 — Join the Domain

1. Open **PowerShell as Administrator** on VMM01.
2. Join the machine to the domain, placing the computer object in the correct OU:

   ```powershell
   $domainPass = ConvertTo-SecureString 'YourPassword' -AsPlainText -Force
   $domainCred = New-Object PSCredential('LAB\Administrator', $domainPass)

   Add-Computer -DomainName 'lab.local' `
                -Credential $domainCred `
                -OUPath 'OU=Servers,OU=Computers,OU=NETS,DC=lab,DC=local' `
                -Force
   ```

   > Replace `lab.local`, `LAB`, and the OU path with your environment's values.

3. **Reboot** the server after the domain join completes.

   ```powershell
   Restart-Computer -Force
   ```

4. After reboot, verify the machine is joined to the domain:

   ```powershell
   (Get-WmiObject Win32_ComputerSystem).Domain
   ```

---

## Stage 2 — Stage Software Locally on VMM01

> ⚠️ **Critical Note:** All installers must be copied to local disk **before** running. The automation was written specifically to avoid running setup directly from a UNC/SMB path due to SMB session hangs causing deadlocked or orphaned installer processes.

### 2a — Stage the Windows ADK

1. Copy the full ADK offline layout to `C:\ADKSetup\` on VMM01.
   - Source: `\\<FileServer>\LabSources\ADK\` (or equivalent)
   - Verify `C:\ADKSetup\adksetup.exe` exists after the copy.

2. Copy the full ADK WinPE Add-on layout to `C:\ADKWinPESetup\` on VMM01.
   - Source: `\\<FileServer>\LabSources\ADKWinPE\`
   - Verify `C:\ADKWinPESetup\adkwinpesetup.exe` exists after the copy.

### 2b — Stage the SCVMM Installer and MSI Prerequisites

1. Create `C:\SCVMMSetup\` on VMM01.
2. Copy the full SCVMM 2025 installer layout into `C:\SCVMMSetup\`.
   - Source: `\\<FileServer>\LabSources\SCVMM2025\`
   - Verify `C:\SCVMMSetup\setup.exe` exists after the copy.
3. Copy the following MSI files into `C:\SCVMMSetup\`:
   - `msodbcsql.msi` — ODBC Driver for SQL Server
   - `MsSqlCmdLnUtils.msi` — SQL Command Line Utilities (sqlcmd)

---

## Stage 3 — Install Windows ADK

> **Check first:** If `C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools` already exists, ADK is installed — skip this stage.

### 3a — Install ADK Core (Deployment Tools feature only)

Run the following from an elevated PowerShell prompt:

```powershell
Start-Process 'C:\ADKSetup\adksetup.exe' `
    -ArgumentList '/quiet /norestart /features OptionId.DeploymentTools' `
    -Wait -PassThru
```

Expected exit codes: `0` (success), `3010` (success, reboot required), `1638` (already installed).

### 3b — Install ADK WinPE Add-on

```powershell
Start-Process 'C:\ADKWinPESetup\adkwinpesetup.exe' `
    -ArgumentList '/quiet /norestart /features OptionId.WindowsPreinstallationEnvironment' `
    -Wait -PassThru
```

Expected exit codes: `0`, `3010`, `1638`.

### 3c — Reboot After ADK Install

```powershell
Restart-Computer -Force
```

---

## Stage 4 — Prepare Active Directory

These steps are performed on a **Domain Controller** (DC01) with the Active Directory PowerShell module available.

### 4a — Create the SCVMM Service Account (`svc_vmm`)

```powershell
Import-Module ActiveDirectory

$secPass = ConvertTo-SecureString 'YourPassword' -AsPlainText -Force

New-ADUser -Name 'svc_vmm' `
           -SamAccountName 'svc_vmm' `
           -UserPrincipalName 'svc_vmm@lab.local' `
           -AccountPassword $secPass `
           -Enabled $true `
           -PasswordNeverExpires $true `
           -Path 'OU=ServiceAccounts,OU=Users,OU=NETS,DC=lab,DC=local'
```

> ⚠️ **Production Note:** `PasswordNeverExpires $true` is set for lab use. In production, implement a managed service account (gMSA) or enforce a controlled password rotation policy instead.

### 4b — Create the SCVMM DKM Container in AD

SCVMM uses a Distributed Key Management (DKM) container in Active Directory to store encryption keys securely.

```powershell
Import-Module ActiveDirectory

New-ADObject -Name 'VMMServer' `
             -Type 'container' `
             -Path 'CN=System,DC=lab,DC=local'
```

This creates the container at: `CN=VMMServer,CN=System,DC=lab,DC=local`

> This path must match the `TopContainerName` value used in the SCVMM unattend INI (see Stage 6).

### 4c — Add `svc_vmm` to Local Administrators on VMM01

Return to **VMM01** and run the following:

```powershell
$group  = [ADSI]'WinNT://./Administrators,group'
$member = 'WinNT://LAB/svc_vmm,user'
$group.Add($member)
```

Verify membership:

```powershell
net localgroup Administrators
```

---

## Stage 5 — Pre-Installation Fixes

### 5a — Disable SQL Server Force Encryption on DB01

> ⚠️ **Known Issue:** SCVMM's setup connects to SQL Server during installation. If SQL Server has **Force Encryption** enabled, the SCVMM installer cannot establish its initial connection and the install will fail silently or error out. This setting must be disabled before running SCVMM setup.

Run the following on **DB01**:

```powershell
$regBase = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'

# Find the instance key (e.g., MSSQL16.MSSQLSERVER)
$instance = Get-ChildItem $regBase |
            Where-Object { $_.PSChildName -match '^MSSQL\d+\.MSSQLSERVER$' } |
            Select-Object -First 1 -ExpandProperty PSChildName

$regPath = "$regBase\$instance\MSSQLServer\SuperSocketNetLib"

# Disable Force Encryption
Set-ItemProperty $regPath -Name 'ForceEncryption' -Value 0

# Restart SQL Server to apply the change
Restart-Service MSSQLSERVER -Force
Start-Sleep -Seconds 5
```

Verify the change:

```powershell
Get-ItemProperty $regPath | Select-Object ForceEncryption
# Expected: ForceEncryption = 0
```

### 5b — Apply .NET Framework TLS Registry Fix on VMM01

SCVMM's installer and the VMM service communicate with SQL Server over TLS. Without this registry fix, .NET Framework may fail to negotiate a TLS connection, causing cryptic failures.

Run the following on **VMM01**:

```powershell
foreach ($path in @(
    'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
)) {
    New-Item $path -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty $path -Name 'SystemDefaultTlsVersions' -Value 1 -Type DWord
    Set-ItemProperty $path -Name 'SchUseStrongCrypto'        -Value 1 -Type DWord
}
Write-Host "TLS fix applied."
```

---

## Stage 6 — Install SCVMM Prerequisites

> ⚠️ **Note:** Run all prerequisite installers before launching SCVMM `setup.exe`. SCVMM's own prerequisites folder is used for .NET and VCRedist; the ODBC and sqlcmd MSIs were staged separately in Stage 2.

From an elevated PowerShell on **VMM01**, install each prerequisite in order:

### 6a — .NET Framework 4.5

```powershell
Start-Process 'C:\SCVMMSetup\Prerequisites\DotNetFx45\dotNetFx45_Full_x86_x64.exe' `
    -ArgumentList '/q /norestart' -Wait -PassThru
```

### 6b — Visual C++ Redistributable (x64)

```powershell
Start-Process 'C:\SCVMMSetup\Prerequisites\VCRedist\amd64\vcredist_x64.exe' `
    -ArgumentList '/quiet /norestart' -Wait -PassThru
```

### 6c — ODBC Driver for SQL Server

```powershell
Start-Process msiexec.exe `
    -ArgumentList '/i "C:\SCVMMSetup\msodbcsql.msi" /quiet /norestart IACCEPTMSODBCSQLLICENSETERMS=YES' `
    -Wait -PassThru
```

### 6d — SQL Command Line Utilities (sqlcmd)

```powershell
Start-Process msiexec.exe `
    -ArgumentList '/i "C:\SCVMMSetup\MsSqlCmdLnUtils.msi" /quiet /norestart IACCEPTMSSQLCMDLNUTILSLICENSETERMS=YES' `
    -Wait -PassThru
```

For all installers, acceptable exit codes are: `0` (success), `3010` (success, reboot required), `1638` (version already installed).

---

## Stage 7 — Create the SCVMM Unattend INI File

Create the file `C:\SCVMMSetup\VMServer.ini` with the following content. Replace all placeholder values with your environment's actual values.

```ini
[OPTIONS]
UserName=Administrator
CompanyName=YourCompany
ProductKey=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
CreateNewSqlDatabase=1
SqlInstanceName=MSSQLSERVER
SqlDatabaseName=VirtualManagerDB
SqlMachineName=DB01.lab.local
IndigoTcpPort=8100
IndigoHTTPSPort=8101
IndigoNETTCPPort=8102
IndigoHTTPPort=8103
WSManTcpPort=5985
BitsTcpPort=443
CreateNewLibraryShare=1
LibraryShareName=MSSCVMMLibrary
LibrarySharePath=C:\ProgramData\Virtual Machine Manager Library Files
SQMOptIn=0
MUOptIn=0
VmmServiceLocalAccount=0
VmmServiceDomain=LAB
VmmServiceUserName=svc_vmm
VmmServiceUserPassword=YourPassword
TopContainerName=CN=VMMServer,CN=System,DC=lab,DC=local
HighlyAvailable=0
```

### INI Field Reference

| Key | Value / Notes |
|---|---|
| `ProductKey` | 25-character product key. Leave blank for evaluation/volume-licensed builds. |
| `CreateNewSqlDatabase` | `1` = create a new database. Use `0` if attaching to an existing DB. |
| `SqlInstanceName` | SQL Server instance name. Default instance = `MSSQLSERVER`. |
| `SqlDatabaseName` | Name of the VMM database to create. |
| `SqlMachineName` | **FQDN** of the SQL Server host. Must be resolvable from VMM01. |
| `IndigoTcpPort` | VMM service port (default: 8100). |
| `IndigoHTTPSPort` | VMM HTTPS port (default: 8101). |
| `IndigoNETTCPPort` | VMM Net.TCP port (default: 8102). |
| `IndigoHTTPPort` | VMM HTTP port (default: 8103). |
| `WSManTcpPort` | WinRM port (default: 5985). |
| `BitsTcpPort` | BITS transfer port (default: 443). |
| `CreateNewLibraryShare` | `1` = create a new VMM library share. |
| `LibraryShareName` | Share name for the VMM library. |
| `LibrarySharePath` | Local path on VMM01 where library files are stored. |
| `SQMOptIn` | `0` = opt out of telemetry. |
| `MUOptIn` | `0` = opt out of Microsoft Update for SCVMM. |
| `VmmServiceLocalAccount` | `0` = use a domain account (recommended). `1` = use Local System. |
| `VmmServiceDomain` | NetBIOS domain name for the VMM service account. |
| `VmmServiceUserName` | Username of the VMM service account (e.g., `svc_vmm`). |
| `VmmServiceUserPassword` | Password for the VMM service account. |
| `TopContainerName` | Full DN of the DKM container created in Stage 4b. |
| `HighlyAvailable` | `0` = standalone install. `1` = clustered (HA) install. |

> ⚠️ **Known Issue — INI Parsing:** SCVMM's `/f` INI parser does **not** resolve double-backslash paths (`C:\\path`). If the INI file is generated by a script that doubles backslashes, `SqlInstanceName`, `SqlDBAdminName`, and other fields will be read as blank by the installer, and the install will proceed silently with missing configuration. Always verify the INI file is written with single backslashes before running setup.

---

## Stage 8 — Verify SQL Connectivity

Before running SCVMM setup, confirm that VMM01 can reach SQL Server on port 1433:

```powershell
$result = Test-NetConnection -ComputerName 'DB01.lab.local' -Port 1433 -WarningAction SilentlyContinue
if ($result.TcpTestSucceeded) {
    Write-Host "SQL connectivity: OK"
} else {
    Write-Host "FAILED — cannot reach DB01:1433. Check firewall rules and SQL Server is running."
}
```

Do **not** proceed until this test passes.

---

## Stage 9 — Run the SCVMM Installer

> ⚠️ **Critical Known Issue — WinRM / RDP Session Deadlock:**
>
> SCVMM's `setup.exe` **reconfigures WinRM mid-install**. If you launch `setup.exe` directly inside a WinRM session (e.g., via PowerShell remoting or any remote management tool that uses WinRM as its transport), the following will happen:
>
> - Setup kills the active WinRM session.
> - The setup process becomes orphaned with no controlling session.
> - Two "Virtual Machine Manager Setup" processes appear in Task Manager but never complete.
> - No setup log is written.
> - The task times out.
>
> **Fix:** Run `setup.exe` via **Windows Task Scheduler** (runs as a background job outside of any WinRM session), or run it **directly from an interactive console session** (RDP/local logon). **Do not** launch it from a remote PowerShell session.

### Option A — Interactive / RDP Install (Recommended for Manual Installs)

If you are logged in via RDP or at the physical/virtual console, run:

```powershell
$setupArgs  = '/server /i'
$setupArgs += ' /f "C:\SCVMMSetup\VMServer.ini"'
$setupArgs += ' /SqlDBAdminDomain LAB'
$setupArgs += ' /SqlDBAdminName Administrator'
$setupArgs += ' /SqlDBAdminPassword "YourPassword"'
$setupArgs += ' /VmmServiceDomain LAB'
$setupArgs += ' /VmmServiceUserName svc_vmm'
$setupArgs += ' /VmmServiceUserPassword "YourPassword"'
$setupArgs += ' /IACCEPTSCEULA'

Start-Process 'C:\SCVMMSetup\setup.exe' -ArgumentList $setupArgs -Wait -PassThru
```

> ⚠️ **Known Issue — `$args` Reserved Variable:** Do **not** use `$args` as the variable name for the argument string in PowerShell. `$args` is a PowerShell reserved automatic variable that holds unbound positional parameters. In a scheduled task or SYSTEM context, this variable collides and causes CLI flags to be silently dropped, resulting in blank credential fields in the setup log. Use a different variable name such as `$setupArgs`.

### Option B — Scheduled Task (for Remote / Automated Runs)

If you must trigger the install remotely (over WinRM), launch it via a scheduled task:

1. **Create the wrapper script** at `C:\SCVMMSetup\run_scvmm_install.ps1`:

   ```powershell
   $logDir   = 'C:\ProgramData\VMMLogs'
   New-Item $logDir -ItemType Directory -Force | Out-Null
   $sentinel = "$logDir\ansible_install.running"
   $exitFile = "$logDir\ansible_install.exitcode"
   Set-Content $sentinel 'running' -Encoding ASCII
   Remove-Item $exitFile -Force -ErrorAction SilentlyContinue

   $setupArgs  = '/server /i'
   $setupArgs += ' /f "C:\SCVMMSetup\VMServer.ini"'
   $setupArgs += ' /SqlDBAdminDomain LAB'
   $setupArgs += ' /SqlDBAdminName Administrator'
   $setupArgs += ' /SqlDBAdminPassword "YourPassword"'
   $setupArgs += ' /VmmServiceDomain LAB'
   $setupArgs += ' /VmmServiceUserName svc_vmm'
   $setupArgs += ' /VmmServiceUserPassword "YourPassword"'
   $setupArgs += ' /IACCEPTSCEULA'

   $r = Start-Process 'C:\SCVMMSetup\setup.exe' -ArgumentList $setupArgs -Wait -PassThru
   Set-Content $exitFile $r.ExitCode -Encoding ASCII
   Remove-Item $sentinel -Force -ErrorAction SilentlyContinue
   ```

2. **Register and start the scheduled task:**

   ```powershell
   $action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
                   -Argument '-NonInteractive -ExecutionPolicy Bypass -File C:\SCVMMSetup\run_scvmm_install.ps1'
   $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2)

   Register-ScheduledTask -TaskName 'SCVMMInstall' `
       -Action $action `
       -Settings $settings `
       -User 'LAB\Administrator' `
       -Password 'YourPassword' `
       -RunLevel Highest `
       -Force

   Start-ScheduledTask -TaskName 'SCVMMInstall'
   ```

3. **Monitor progress** by watching the exit code file:

   ```powershell
   $exitFile = 'C:\ProgramData\VMMLogs\ansible_install.exitcode'
   $sentinel = 'C:\ProgramData\VMMLogs\ansible_install.running'

   while ($true) {
       Start-Sleep -Seconds 30
       $taskState  = (Get-ScheduledTask -TaskName 'SCVMMInstall' -ErrorAction SilentlyContinue).State
       $exitExists = Test-Path $exitFile
       $running    = Test-Path $sentinel
       Write-Host "Task state: $taskState | Exit written: $exitExists | Sentinel: $running"

       if ($exitExists) {
           $code = [int](Get-Content $exitFile -Raw).Trim()
           Write-Host "SCVMM installer exited with code: $code"
           break
       }
   }
   ```

4. Expected exit codes: `0` (success), `3010` (success, reboot required).

### Setup Command-Line Arguments Reference

| Argument | Description |
|---|---|
| `/server` | Install the VMM Server component. |
| `/i` | Perform an installation (as opposed to uninstall). |
| `/f <path>` | Path to the unattend INI file. |
| `/SqlDBAdminDomain` | NetBIOS domain of the SQL admin account used during setup. |
| `/SqlDBAdminName` | Username of the SQL admin account (must have `sysadmin` rights on SQL). |
| `/SqlDBAdminPassword` | Password for the SQL admin account. |
| `/VmmServiceDomain` | NetBIOS domain for the VMM service account. |
| `/VmmServiceUserName` | Username of the VMM service account (`svc_vmm`). |
| `/VmmServiceUserPassword` | Password for the VMM service account. |
| `/IACCEPTSCEULA` | Accept the System Center EULA (required for unattended install). |

---

## Stage 10 — Post-Install Verification

After the installer completes, verify the installation was successful:

### 10a — Check the VMM Service

```powershell
Get-Service SCVMMService | Select-Object Name, Status, StartType
```

Expected: `Status = Running`, `StartType = Automatic`.

### 10b — Check the Setup Log

The primary setup log is located at:

```
C:\ProgramData\VMMLogs\SetupWizard.log
```

Look for errors or warnings, especially around:
- SQL Server connectivity
- Service account configuration
- DKM container access

### 10c — Open the VMM Console

Launch the VMM Administrator Console from Start Menu or:

```
C:\Program Files\Microsoft System Center\Virtual Machine Manager\bin\VmmAdminUI.exe
```

Connect to `VMM01.lab.local` on port `8100`.

### 10d — Verify the VMM Library Share

Confirm the library share was created:

```powershell
Get-SmbShare -Name MSSCVMMLibrary
```

Verify the path exists:

```powershell
Test-Path 'C:\ProgramData\Virtual Machine Manager Library Files'
```

### 10e — Reboot if Required

If the setup exit code was `3010`, reboot VMM01:

```powershell
Restart-Computer -Force
```

---

## Known Issues Summary

| # | Issue | Impact | Resolution |
|---|---|---|---|
| 1 | **SMB Hangs During Install** | Installer orphans, never completes | Stage all installers locally to `C:\` before running. Never run setup directly from a network share. |
| 2 | **WinRM Session Deadlock** | Setup reconfigures WinRM mid-install, killing the remote session; two orphaned VMM setup processes appear in Task Manager, no log is written | Launch `setup.exe` from a **Scheduled Task** or an **interactive RDP/console session** — never from within a WinRM-based remote session. |
| 3 | **Double-Backslash INI Parsing Bug** | All INI fields (SqlInstanceName, credentials, etc.) silently read as blank; install proceeds but is misconfigured | Ensure the `VMServer.ini` file contains **single backslashes** in all paths. Verify the raw file content before running setup. |
| 4 | **`$args` Variable Collision** | CLI flags silently dropped under Scheduled Task / SYSTEM context; credential fields blank in setup log | Never use `$args` as a variable name in PowerShell scripts. Use `$setupArgs` or any other name. |
| 5 | **SQL Server Force Encryption** | SCVMM installer cannot establish a SQL connection during setup | Disable `ForceEncryption` in the SQL Server registry on DB01 and restart the SQL service **before** running SCVMM setup. Re-enable after install if required by policy. |
| 6 | **TLS Negotiation Failures (.NET)** | Cryptic connection failures between VMM service and SQL Server | Apply the `SystemDefaultTlsVersions` and `SchUseStrongCrypto` registry keys to both the 64-bit and WOW6432Node .NET Framework v4 hive on VMM01. |
| 7 | **DB01 Must Be Configured First** | SCVMM setup will fail if SQL Server is not ready | Fully provision and verify DB01 before beginning any SCVMM installation steps. Confirm port 1433 is reachable from VMM01. |

---

## Quick Reference: Key Paths

| Item | Path |
|---|---|
| ADK setup staging | `C:\ADKSetup\adksetup.exe` |
| ADK WinPE staging | `C:\ADKWinPESetup\adkwinpesetup.exe` |
| SCVMM installer staging | `C:\SCVMMSetup\setup.exe` |
| SCVMM unattend INI | `C:\SCVMMSetup\VMServer.ini` |
| Install wrapper script | `C:\SCVMMSetup\run_scvmm_install.ps1` |
| VMM Logs directory | `C:\ProgramData\VMMLogs\` |
| Setup wizard log | `C:\ProgramData\VMMLogs\SetupWizard.log` |
| VMM Library Files | `C:\ProgramData\Virtual Machine Manager Library Files` |
| ADK install path | `C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\` |

## Quick Reference: Key Ports

| Port | Protocol | Purpose |
|---|---|---|
| 8100 | TCP | VMM service (Indigo TCP) |
| 8101 | TCP | VMM HTTPS |
| 8102 | TCP | VMM Net.TCP |
| 8103 | TCP | VMM HTTP |
| 5985 | TCP | WinRM (WSMan) |
| 443 | TCP | BITS transfer |
| 1433 | TCP | SQL Server |
