#Requires -RunAsAdministrator
# Packer provisioner: 03-sysprep.ps1 (Win11)

$ErrorActionPreference = 'Stop'

Write-Host '=== 03-sysprep (Win11): Preparing for generalize... ==='

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f | Out-Null

Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
    -Name PagingFiles -Value ([string[]]@()) -Force

Write-Host 'Scheduling sysprep in 90 seconds...'
$action    = New-ScheduledTaskAction -Execute 'C:\Windows\System32\Sysprep\sysprep.exe' `
                 -Argument '/oobe /generalize /shutdown /quiet'
$trigger   = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(90))
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName 'PackerSysprep' -Action $action `
    -Trigger $trigger -Principal $principal -Force | Out-Null

Write-Host '=== 03-sysprep (Win11): Complete. Sysprep fires in ~90s. ==='
