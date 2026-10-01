#Requires -RunAsAdministrator
# Packer provisioner: 03-sysprep.ps1 (Win11)

$ErrorActionPreference = 'Stop'

Write-Host '=== 03-sysprep (Win11): Preparing for generalize... ==='

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f | Out-Null

Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
    -Name PagingFiles -Value ([string[]]@()) -Force

# Write sysprep unattend so deployed VMs auto-complete OOBE with known credentials
$unattendPath = 'C:\Windows\System32\Sysprep\unattend.xml'
$labAdminPassword = $env:LAB_ADMIN_PASSWORD
if ([string]::IsNullOrWhiteSpace($labAdminPassword)) {
    throw 'LAB_ADMIN_PASSWORD was not provided by the Packer provisioner.'
}
$xmlPassword = [System.Security.SecurityElement]::Escape($labAdminPassword)
$unattendXml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Deployment"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <RunSynchronous>
        <!-- Enable Administrator account before OOBE starts on deployed VMs -->
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Path>net user Administrator /active:yes</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <UserAccounts>
        <AdministratorPassword>
          <Value>__LAB_ADMIN_PASSWORD__</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <SkipUserOOBE>true</SkipUserOOBE>
        <SkipMachineOOBE>true</SkipMachineOOBE>
      </OOBE>
    </component>
  </settings>
  <settings pass="oobeSystem">
  </settings>
</unattend>
'@
$unattendXml = $unattendXml.Replace('__LAB_ADMIN_PASSWORD__', $xmlPassword)
Set-Content -LiteralPath $unattendPath -Encoding UTF8 -Value $unattendXml

Write-Host 'Scheduling sysprep in 90 seconds...'
$action    = New-ScheduledTaskAction -Execute 'C:\Windows\System32\Sysprep\sysprep.exe' `
                 -Argument '/oobe /generalize /shutdown /quiet /unattend:C:\Windows\System32\Sysprep\unattend.xml'
$trigger   = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(90))
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName 'PackerSysprep' -Action $action `
    -Trigger $trigger -Principal $principal -Force | Out-Null

Write-Host '=== 03-sysprep (Win11): Complete. Sysprep fires in ~90s. ==='
