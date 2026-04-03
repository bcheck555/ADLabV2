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

# --- PowerShell 7 ---
Write-Host 'Installing PowerShell 7...'
try {
    $ps7Msi = 'C:\Windows\Temp\pwsh7.msi'
    $ps7Url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.msi'
    (New-Object System.Net.WebClient).DownloadFile($ps7Url, $ps7Msi)
    Start-Process msiexec.exe -ArgumentList "/i $ps7Msi /quiet /norestart" -Wait
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

$sshdConfig = @'
# ADLabV2 sshd_config — managed by Packer
Port 22
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Subsystem powershell c:/progra~1/powershell/7/pwsh.exe -sshs -nologo
'@
Set-Content 'C:\ProgramData\ssh\sshd_config' $sshdConfig -Force -Encoding UTF8
Restart-Service sshd

New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
    -DisplayName 'OpenSSH Server (sshd)' `
    -Direction Inbound -Protocol TCP -LocalPort 22 `
    -Action Allow -Profile Any -Force | Out-Null

Write-Host '=== 02-configure (Win11): Complete ==='
