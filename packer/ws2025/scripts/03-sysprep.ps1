#Requires -RunAsAdministrator
# Packer provisioner: 03-sysprep.ps1
# Pre-sysprep cleanup. Sysprep fires via a scheduled task ~90s after this exits.
#
# NOTE: Do NOT remove Appx provisioned packages here. Partial removal causes
# sysprep to fail. See: https://learn.microsoft.com/en-us/troubleshoot/windows-client/
# setup-upgrade-and-drivers/sysprep-fails-remove-or-update-store-apps

$ErrorActionPreference = 'Stop'

Write-Host '=== 03-sysprep: Preparing for generalize... ==='

# Disable Defender via registry (bypasses Tamper Protection)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f | Out-Null

# Remove pagefile to shrink VHD
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
    -Name PagingFiles -Value ([string[]]@()) -Force

# Schedule sysprep via one-shot scheduled task (avoids WinRM staleness issues)
Write-Host 'Scheduling sysprep in 90 seconds...'
$action    = New-ScheduledTaskAction -Execute 'C:\Windows\System32\Sysprep\sysprep.exe' `
                 -Argument '/oobe /generalize /shutdown /quiet'
$trigger   = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(90))
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName 'PackerSysprep' -Action $action `
    -Trigger $trigger -Principal $principal -Force | Out-Null

Write-Host '=== 03-sysprep: Complete. Sysprep fires via scheduled task in ~90s. ==='
