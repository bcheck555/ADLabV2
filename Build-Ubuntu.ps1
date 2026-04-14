#Requires -RunAsAdministrator
# Build-Ubuntu.ps1

$ErrorActionPreference = 'Stop'
$LabRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Import-PowerShellDataFile "$LabRoot\config\lab.config.psd1"

$PackerDir = Join-Path $cfg.PackerDir 'ubuntu2404'
$OutputDir = Join-Path $PackerDir 'output'

Push-Location $PackerDir
try {
    Write-Host "Starting Ubuntu 24.04 Packer build..." -ForegroundColor Cyan
    Write-Host "This will take 30-60 minutes" -ForegroundColor Yellow
    Write-Host ""

    # Add packer tools to PATH for oscdimg
    $packerToolDir = Split-Path -Parent $cfg.PackerExe
    $env:PATH = "$packerToolDir;$env:PATH"

    & packer init .
    if ($LASTEXITCODE -ne 0) { throw "packer init failed" }

    & packer build `
        -var "iso_path=$($cfg.Ubuntu2404ISO)" `
        -var "output_dir=$OutputDir" `
        -var "switch_name=$($cfg.PackerSwitch)" `
        -var "ssh_pass=$($cfg.LinuxPass)" `
        .
    if ($LASTEXITCODE -ne 0) { throw "packer build failed" }

    Write-Host "`nUbuntu build complete!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
