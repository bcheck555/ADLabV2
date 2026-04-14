#Requires -RunAsAdministrator
# Setup-Packer.ps1 - Prepare for Packer builds

$ErrorActionPreference = 'Stop'
$LabRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Import-PowerShellDataFile "$LabRoot\config\lab.config.psd1"

Write-Host "`n=== Packer Setup ===" -ForegroundColor Cyan

# 1. Create PackerSwitch
Write-Host "`n[1/3] Checking $($cfg.PackerSwitch)..." -NoNewline
$switch = Get-VMSwitch -Name $cfg.PackerSwitch -ErrorAction SilentlyContinue
if ($switch) {
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host " Creating..." -ForegroundColor Yellow
    New-VMSwitch -Name $cfg.PackerSwitch -SwitchType Internal -ErrorAction Stop
    Write-Host " Created" -ForegroundColor Green
}

# 2. Check ISOs
Write-Host "[2/3] Checking ISOs..." -ForegroundColor Cyan
$isoCfg = @{
    'WS2025' = $cfg.WS2025ISO
    'Win11'  = $cfg.Win11ISO
    'Ubuntu' = $cfg.Ubuntu2404ISO
}

$allExists = $true
foreach ($name in $isoCfg.Keys) {
    $path = $isoCfg[$name]
    $exists = Test-Path $path
    $symbol = if ($exists) { "OK" } else { "MISSING" }
    Write-Host "  [$symbol] $name -> $path"
    if (-not $exists) { $allExists = $false }
}

if (-not $allExists) {
    Write-Host "  Some ISOs are missing!" -ForegroundColor Red
    Write-Host "  Cannot proceed with Packer builds." -ForegroundColor Red
    exit 1
}

# 3. Check Packer
Write-Host "[3/3] Checking OpenTofu..." -NoNewline
$tofu = Get-Command tofu -ErrorAction SilentlyContinue
if ($tofu) {
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host " MISSING" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Ready to build. Starting Packer builds... ===" -ForegroundColor Green
Write-Host "This will take 30-60 minutes per image." -ForegroundColor Yellow
