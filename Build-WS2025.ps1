#Requires -RunAsAdministrator
# Build-WS2025.ps1

$ErrorActionPreference = 'Stop'
$LabRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Import-PowerShellDataFile "$LabRoot\config\lab.config.psd1"
if ([string]::IsNullOrWhiteSpace($env:AD_LAB_ADMIN_PASSWORD)) {
    throw 'Set AD_LAB_ADMIN_PASSWORD in this PowerShell process before building the image.'
}
$previousPackerPassword = [Environment]::GetEnvironmentVariable('PKR_VAR_ssh_pass', 'Process')
$env:PKR_VAR_ssh_pass = $env:AD_LAB_ADMIN_PASSWORD

$PackerDir = Join-Path $cfg.PackerDir 'ws2025'
$OutputDir = Join-Path $PackerDir 'output'

Push-Location $PackerDir
try {
    Write-Host "Starting WS2025 Packer build..." -ForegroundColor Cyan
    Write-Host "This will take 30-60 minutes" -ForegroundColor Yellow
    Write-Host ""

    # Keep packer.exe available and add the ADK ISO tool for this build process.
    $packerToolDir = Split-Path -Parent $cfg.PackerExe
    $env:PATH = "$packerToolDir;$env:PATH"
    . (Join-Path $LabRoot 'Packer-HostTools.ps1')
    Initialize-PackerIsoToolPath | Out-Null
    Assert-PackerHostNetwork -SwitchName $cfg.PackerSwitch -IPAddress $cfg.PackerBuildGw -PrefixLength $cfg.PackerBuildPfx | Out-Null

    & packer init .
    if ($LASTEXITCODE -ne 0) { throw "packer init failed" }

    & packer build `
        -var "iso_path=$($cfg.WS2025ISO)" `
        -var "output_dir=$OutputDir" `
        -var "switch_name=$($cfg.PackerSwitch)" `
        .
    if ($LASTEXITCODE -ne 0) { throw "packer build failed" }

    Write-Host "`nWS2025 build complete!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
    if ($null -eq $previousPackerPassword) {
        Remove-Item Env:PKR_VAR_ssh_pass -ErrorAction SilentlyContinue
    } else {
        $env:PKR_VAR_ssh_pass = $previousPackerPassword
    }
}
