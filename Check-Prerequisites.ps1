#Requires -RunAsAdministrator
# Check-Prerequisites.ps1 - Verify ADLabV2 build requirements

$ErrorActionPreference = 'Continue'
$LabRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Import-PowerShellDataFile (Join-Path $LabRoot 'config\lab.config.psd1')

Write-Host "`n=== ADLabV2 Prerequisites Check ===" -ForegroundColor Cyan

# 1. Hyper-V
Write-Host "`n[1/5] Hyper-V Feature..." -NoNewline
$hvFeature = Get-WindowsOptionalFeature -FeatureName Hyper-V -Online
if ($hvFeature.State -eq 'Enabled') {
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host " MISSING (State: $($hvFeature.State))" -ForegroundColor Red
}

# 2. Lab switch
Write-Host "[2/5] $($cfg.SwitchName) switch..." -NoNewline
$switch = Get-VMSwitch -Name $cfg.SwitchName -ErrorAction SilentlyContinue
if ($switch) {
    Write-Host " OK ($($switch.SwitchType))" -ForegroundColor Green
} else {
    Write-Host " MISSING" -ForegroundColor Red
    Write-Host "       → Run the ad-hyperv-lab Ansible playbook to create $($cfg.SwitchName) and its NAT." -ForegroundColor Yellow
}

# 3. OpenTofu
Write-Host "[3/5] OpenTofu..." -NoNewline
$tofu = (Get-Command tofu -ErrorAction SilentlyContinue)
if ($tofu) {
    $version = & tofu version 2>&1 | head -1
    Write-Host " OK ($version)" -ForegroundColor Green
} else {
    Write-Host " MISSING" -ForegroundColor Red
    Write-Host "       → Download from: https://opentofu.org/download/" -ForegroundColor Yellow
}

# 4. Docker
Write-Host "[4/5] Docker..." -NoNewline
$docker = (Get-Command docker -ErrorAction SilentlyContinue)
if ($docker) {
    $version = & docker version --format '{{.Server.Version}}' 2>&1
    Write-Host " OK ($version)" -ForegroundColor Green
} else {
    Write-Host " MISSING" -ForegroundColor Red
    Write-Host "       → Install Docker Desktop" -ForegroundColor Yellow
}

# 5. Base VHDs
Write-Host "[5/5] Base VHDs..." -NoNewline
$cfg = Import-PowerShellDataFile "$LabRoot\config\lab.config.psd1"
$vhdMissing = @()
foreach ($vhd in @($cfg.WS2025BaseVHD, $cfg.Win11BaseVHD, $cfg.Ubuntu2404BaseVHD)) {
    if (-not (Test-Path $vhd)) {
        $vhdMissing += (Split-Path -Leaf $vhd)
    }
}

if ($vhdMissing.Count -eq 0) {
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host " MISSING ($($vhdMissing -join ', '))" -ForegroundColor Red
    Write-Host "       → Run packer builds: packer build -var-file=vars.pkrvars.hcl <image>.pkr.hcl" -ForegroundColor Yellow
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Once all prerequisites are met, run: .\Build-Lab.ps1`n"
