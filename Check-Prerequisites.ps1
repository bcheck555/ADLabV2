#Requires -RunAsAdministrator
# Check-Prerequisites.ps1 - Verify ADLabV2 build requirements

$ErrorActionPreference = 'Continue'
$LabRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Import-PowerShellDataFile (Join-Path $LabRoot 'config\lab.config.psd1')

. (Join-Path $LabRoot 'Packer-HostTools.ps1')

Write-Host "`n=== ADLabV2 Prerequisites Check ===" -ForegroundColor Cyan

# 1. Hyper-V
Write-Host "`n[1/5] Hyper-V Feature..." -NoNewline
$hvState = $null
if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
    # Windows Server exposes roles and features through ServerManager.
    $hvFeature = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue
    if ($hvFeature) { $hvState = [string]$hvFeature.InstallState }
} else {
    # Windows client editions expose optional features through DISM.
    $hvFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
    if ($hvFeature) { $hvState = [string]$hvFeature.State }
}

if ($hvState -in @('Installed', 'Enabled')) {
    Write-Host " OK ($hvState)" -ForegroundColor Green
} elseif ($hvState) {
    Write-Host " MISSING (State: $hvState)" -ForegroundColor Red
} else {
    Write-Host " UNKNOWN (unable to query feature state)" -ForegroundColor Yellow
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
    $tofuOutput = & $tofu.Source version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $version = $tofuOutput | Select-Object -First 1
        Write-Host " OK ($version)" -ForegroundColor Green
    } else {
        Write-Host " FOUND, VERSION CHECK FAILED" -ForegroundColor Yellow
        Write-Host "       → Check that tofu.exe can run from this PowerShell session." -ForegroundColor Yellow
    }
} else {
    Write-Host " MISSING" -ForegroundColor Red
    Write-Host "       → Download from: https://opentofu.org/download/" -ForegroundColor Yellow
}

# 4. Docker
Write-Host "[4/5] Docker..." -NoNewline
$docker = (Get-Command docker -ErrorAction SilentlyContinue)
if ($docker) {
    $cliVersion = & $docker.Source --version 2>&1
    if ($LASTEXITCODE -ne 0) { $cliVersion = 'Docker CLI found' }
    $engineVersion = & $docker.Source version --format '{{.Server.Version}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $engineVersion) {
        Write-Host " OK ($cliVersion; Engine $engineVersion)" -ForegroundColor Green
    } else {
        Write-Host " INSTALLED ($cliVersion), ENGINE UNAVAILABLE" -ForegroundColor Yellow
        Write-Host "       → Start Docker Desktop or the Docker Engine service before building." -ForegroundColor Yellow
    }
} else {
    Write-Host " MISSING" -ForegroundColor Red
    Write-Host "       → Install Docker Desktop" -ForegroundColor Yellow
}

# 5. Packer host adapter
Write-Host "[5/7] Packer host adapter..." -NoNewline
$packerNetwork = Get-PackerHostNetworkStatus -SwitchName $cfg.PackerSwitch -IPAddress $cfg.PackerBuildGw -PrefixLength $cfg.PackerBuildPfx
if ($packerNetwork) {
    Write-Host " OK ($($packerNetwork.IPAddress)/$($packerNetwork.PrefixLength))" -ForegroundColor Green
} else {
    Write-Host " MISSING OR MISCONFIGURED" -ForegroundColor Red
    Write-Host "       → Run .\Setup-Packer.ps1 from elevated PowerShell to configure the host vNIC." -ForegroundColor Yellow
}

# 6. Packer ISO creation tool
Write-Host "[6/7] Packer ISO tool (oscdimg)..." -NoNewline
$oscdimgPath = Get-PackerIsoToolPath
if ($oscdimgPath) {
    Initialize-PackerIsoToolPath | Out-Null
    Write-Host " OK ($oscdimgPath)" -ForegroundColor Green
} else {
    Write-Host " MISSING" -ForegroundColor Red
    Write-Host "       → Run .\Setup-Packer.ps1 from elevated PowerShell after populating LabSources." -ForegroundColor Yellow
}

# 7. Base VHDs
Write-Host "[7/7] Base VHDs..." -NoNewline
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
