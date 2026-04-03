#Requires -RunAsAdministrator
# Packer provisioner: 02-configure.ps1 (WS2025)
# Baseline OS configuration + OpenSSH + PowerShell 7 for Ansible SSH transport.

$ErrorActionPreference = 'Stop'

Write-Host '=== 02-configure: Starting ==='

# --- OS Baseline ---
Write-Host 'Disabling Windows Update...'
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Set-Service wuauserv -StartupType Disabled
Set-Service UsoSvc   -StartupType Disabled -ErrorAction SilentlyContinue

Write-Host 'Disabling Defender real-time monitoring...'
Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f | Out-Null

Set-TimeZone -Id 'UTC'
powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
powercfg.exe /hibernate off

Write-Host 'Enabling Remote Desktop...'
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 0
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' UserAuthentication 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'

# Disable IE ESC
$ieAdminKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}'
$ieUserKey  = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}'
Set-ItemProperty -Path $ieAdminKey -Name IsInstalled -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ieUserKey  -Name IsInstalled -Value 0 -ErrorAction SilentlyContinue

New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name DoNotOpenServerManagerAtLogon `
    -Value 1 -PropertyType DWORD -Force | Out-Null

Get-NetAdapterBinding -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -ErrorAction SilentlyContinue

# --- PowerShell 7 ---
# Required as the OpenSSH subsystem shell for Ansible.
# winget is available in WS2025 evaluation ISO. Falls back to direct MSI if not.
Write-Host 'Installing PowerShell 7...'
try {
    $ps7Msi = 'C:\Windows\Temp\pwsh7.msi'
    $ps7Url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.msi'
    (New-Object System.Net.WebClient).DownloadFile($ps7Url, $ps7Msi)
    Start-Process msiexec.exe -ArgumentList "/i $ps7Msi /quiet /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1" -Wait
    Remove-Item $ps7Msi -Force -ErrorAction SilentlyContinue
    Write-Host 'PowerShell 7 installed.'
} catch {
    Write-Warning "PS7 download failed: $_. Ansible will fall back to Windows PowerShell 5.1."
}

# --- OpenSSH Server ---
Write-Host 'Installing OpenSSH Server...'
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service sshd -StartupType Automatic

# sshd_config: password auth for initial bootstrap, PS7 subsystem for Ansible
$sshdConfig = @'
# ADLabV2 sshd_config — managed by Packer
Port 22
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# PowerShell 7 subsystem — required for ansible_shell_type=powershell over SSH
Subsystem powershell c:/progra~1/powershell/7/pwsh.exe -sshs -nologo
'@
Set-Content 'C:\ProgramData\ssh\sshd_config' $sshdConfig -Force -Encoding UTF8
Restart-Service sshd

# Firewall rule for SSH
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
    -DisplayName 'OpenSSH Server (sshd)' `
    -Direction Inbound -Protocol TCP -LocalPort 22 `
    -Action Allow -Profile Any -Force | Out-Null

Write-Host '=== 02-configure: Complete ==='
