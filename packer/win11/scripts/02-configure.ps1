#Requires -RunAsAdministrator
# Packer provisioner: 02-configure.ps1 (Win11)
# Baseline OS configuration + OpenSSH + PowerShell 7 for Ansible SSH transport.

$ErrorActionPreference = 'Stop'

Write-Host '=== 02-configure (Win11): Starting ==='

# --- OS Baseline ---
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Set-Service wuauserv  -StartupType Disabled
Set-Service UsoSvc    -StartupType Disabled -ErrorAction SilentlyContinue

Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f | Out-Null

Set-TimeZone -Id 'UTC'
powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
powercfg.exe /hibernate off

Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 0
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' UserAuthentication 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'

Get-NetAdapterBinding -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -ErrorAction SilentlyContinue

# Disable Consumer features / Cortana
$cloudContentKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
New-Item $cloudContentKey -Force | Out-Null
Set-ItemProperty $cloudContentKey DisableWindowsConsumerFeatures 1
$cortanaKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
New-Item $cortanaKey -Force | Out-Null
Set-ItemProperty $cortanaKey AllowCortana 0

# --- PowerShell 7 (from UNATTEND CD) ---
Write-Host 'Installing PowerShell 7...'
$cdDrive = (Get-Volume -FileSystemLabel 'UNATTEND' -ErrorAction SilentlyContinue).DriveLetter
$ps7Msi  = if ($cdDrive) { "${cdDrive}:\PowerShell-7.6.6-win-x64.msi" } else { $null }
if ($ps7Msi -and (Test-Path $ps7Msi)) {
    Start-Process msiexec.exe -ArgumentList "/i `"$ps7Msi`" /quiet /norestart" -Wait
    Write-Host 'PowerShell 7 installed.'
} else {
    Write-Warning 'PS7 MSI not found on UNATTEND CD. Ansible will fall back to Windows PowerShell 5.1.'
}

# --- OpenSSH Server (already installed via MSI in autounattend) ---
# Just ensure the service is running
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service sshd -StartupType Automatic

# Build sshd_config — use PS7 subsystem if available, otherwise PS5.1
$subsystem = if (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') {
    'Subsystem powershell "c:/program files/powershell/7/pwsh.exe" -sshs -nologo'
} else {
    'Subsystem powershell c:/windows/system32/windowspowershell/v1.0/powershell.exe -sshs -nologo'
}
$sshdConfig = @"
# ADLabV2 sshd_config — managed by Packer
Port 22
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
$subsystem
"@
Set-Content 'C:\ProgramData\ssh\sshd_config' $sshdConfig -Force -Encoding UTF8
Restart-Service sshd

New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
    -DisplayName 'OpenSSH Server (sshd)' `
    -Direction Inbound -Protocol TCP -LocalPort 22 `
    -Action Allow -Profile Any | Out-Null

Write-Host '=== 02-configure (Win11): Complete ==='
