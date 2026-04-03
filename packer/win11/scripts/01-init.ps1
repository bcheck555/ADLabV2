#Requires -RunAsAdministrator
# Packer provisioner: 01-init.ps1 (Win11)

$ErrorActionPreference = 'Stop'

Write-Host '=== 01-init (Win11): Starting ==='

$svc = Get-Service WinRM
if ($svc.Status -ne 'Running') { Start-Service WinRM }
winrm set winrm/config/service '@{AllowUnencrypted="true"}' | Out-Null
winrm set winrm/config/service/auth '@{Basic="true"}' | Out-Null

Write-Host 'Expanding C: volume...'
$supportedSize = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
$currentSize   = (Get-Partition -DriveLetter C).Size
if ($supportedSize -gt $currentSize) {
    Resize-Partition -DriveLetter C -Size $supportedSize
    Write-Host "Expanded C: to $([math]::Round($supportedSize/1GB,1)) GB"
} else {
    Write-Host 'C: already at maximum size.'
}

Write-Host '=== 01-init (Win11): Complete ==='
