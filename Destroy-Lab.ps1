#Requires -RunAsAdministrator
# Destroy-Lab.ps1 - Tears down all ADLabV2 VMs via OpenTofu.
# VHDXs and Packer base images are NOT deleted.

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Force  # Skip confirmation prompt
)

$ErrorActionPreference = 'Stop'
$LabRoot = $PSScriptRoot
$cfg = Import-PowerShellDataFile "$LabRoot\config\lab.config.psd1"

if (-not $Force) {
    $confirm = Read-Host "This will destroy all ADLabV2 VMs. Type 'yes' to confirm"
    if ($confirm -ne 'yes') {
        Write-Host 'Aborted.'
        exit 0
    }
}

Write-Host '=== Destroy-Lab: Force-stopping and removing all lab VMs ===' -ForegroundColor Yellow
$labPattern = '^(DC01|DC02|CA01|DB01|WEB01|GIT01|WKS01|WKS02|VMM01)$'
$vmNames = @("DC01", "DC02", "CA01", "DB01", "WEB01", "GIT01", "WKS01", "WKS02", "VMM01")
$vmDir = $cfg.VmDir # Assuming VmDir is set in lab.config.psd1

Get-VM | Where-Object { $_.Name -match $labPattern } | ForEach-Object {
    Write-Host "  Force-stopping and removing $($_.Name)..."
    $_ | Stop-VM -Force -TurnOff -ErrorAction SilentlyContinue
    $_ | Remove-VM -Force -ErrorAction SilentlyContinue
}

Write-Host '=== Destroy-Lab: Deleting VM VHDX files ===' -ForegroundColor Yellow
foreach ($vmName in $vmNames) {
    $vmDiskPath = Join-Path $vmDir $vmName "$vmName.vhdx"
    if (Test-Path $vmDiskPath) {
        Write-Host "  Deleting $vmDiskPath..."
        Remove-Item $vmDiskPath -Force -ErrorAction SilentlyContinue
    }
    $vmFolder = Join-Path $vmDir $vmName
    if (Test-Path $vmFolder) {
        # Attempt to remove the VM's folder if it's empty or contains only other items
        # Be cautious with recursive removal
        try {
            # Check if the folder only contains the vhdx file, and if that file is already deleted
            $itemsInFolder = Get-ChildItem $vmFolder
            if ($itemsInFolder.Count -eq 0) {
                Write-Host "  Removing empty VM folder $vmFolder..."
                Remove-Item $vmFolder -Force -Recurse -ErrorAction SilentlyContinue
            } elseif ($itemsInFolder.Count -eq 1 -and $itemsInFolder[0].Name -eq "$vmName.vhdx" -and -not (Test-Path $itemsInFolder[0].FullName)) {
                 Write-Host "  Removing VM folder $vmFolder (VHDX already deleted)..."
                Remove-Item $vmFolder -Force -Recurse -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "Could not remove folder ${vmFolder}: $($_.Exception.Message)"
        }
    }
}

Write-Host '=== Destroy-Lab: Deleting OpenTofu state files ===' -ForegroundColor Yellow
$terraformDir = Join-Path $LabRoot 'terraform'
$tfStatePath = Join-Path $terraformDir 'terraform.tfstate'
$tfStateBackupPath = Join-Path $terraformDir 'terraform.tfstate.backup'

if (Test-Path $tfStatePath) {
    Write-Host "  Deleting $tfStatePath..."
    Remove-Item $tfStatePath -Force -ErrorAction SilentlyContinue
}
if (Test-Path $tfStateBackupPath) {
    Write-Host "  Deleting $tfStateBackupPath..."
    Remove-Item $tfStateBackupPath -Force -ErrorAction SilentlyContinue
}

Write-Host '=== Destroy-Lab: Complete ===' -ForegroundColor Yellow
Write-Host "Base VHDs preserved at: $($cfg.BaseVhdDir)"
Write-Host 'Run Build-Lab.ps1 to rebuild.'
