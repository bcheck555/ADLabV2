#Requires -RunAsAdministrator
# Destroy-Lab.ps1 — Tears down all ADLabV2 VMs via OpenTofu.
# VHDXs and Packer base images are NOT deleted.

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Force  # Skip confirmation prompt
)

$ErrorActionPreference = 'Stop'
$LabRoot = $PSScriptRoot

if (-not $Force) {
    $confirm = Read-Host "This will destroy all ADLabV2 VMs. Type 'yes' to confirm"
    if ($confirm -ne 'yes') {
        Write-Host 'Aborted.'
        exit 0
    }
}

Write-Host '=== Destroy-Lab: Running tofu destroy ===' -ForegroundColor Yellow

Push-Location "$LabRoot\terraform"
try {
    & tofu init -input=false
    if ($LASTEXITCODE -ne 0) { throw "tofu init failed" }
    & tofu destroy -input=false -auto-approve
    if ($LASTEXITCODE -ne 0) { throw "tofu destroy failed" }
} finally {
    Pop-Location
}

Write-Host '=== Destroy-Lab: Complete ===' -ForegroundColor Yellow
Write-Host 'Base VHDs preserved at: D:\CODE\ADLabV2\base-vhds\'
Write-Host 'Run Build-Lab.ps1 to rebuild.'
