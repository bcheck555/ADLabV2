#Requires -RunAsAdministrator
# Setup-Packer.ps1 - Prepare for Packer builds

$ErrorActionPreference = 'Stop'
$LabRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Import-PowerShellDataFile "$LabRoot\config\lab.config.psd1"

Write-Host "`n=== Packer Setup ===" -ForegroundColor Cyan
. (Join-Path $LabRoot 'Packer-HostTools.ps1')

# 1. Create PackerSwitch
Write-Host "`n[1/4] Checking $($cfg.PackerSwitch)..." -NoNewline
$switch = Get-VMSwitch -Name $cfg.PackerSwitch -ErrorAction SilentlyContinue
if ($switch) {
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host " Creating..." -ForegroundColor Yellow
    New-VMSwitch -Name $cfg.PackerSwitch -SwitchType Internal -ErrorAction Stop
    Write-Host " Created" -ForegroundColor Green
}

# 2. Configure the host vNIC on the isolated Packer network.
Write-Host "[2/4] Configuring Packer host adapter..." -NoNewline
$packerNetwork = Set-PackerHostNetwork -SwitchName $cfg.PackerSwitch -IPAddress $cfg.PackerBuildGw -PrefixLength $cfg.PackerBuildPfx
Write-Host " OK ($($packerNetwork.AdapterName): $($packerNetwork.IPAddress)/$($packerNetwork.PrefixLength))" -ForegroundColor Green

# 3. Check ISOs
Write-Host "[3/4] Checking ISOs..." -ForegroundColor Cyan
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

# 4. Install ADK Deployment Tools when oscdimg is not already available.
Write-Host "[4/4] Checking Packer ISO tool (oscdimg)..." -NoNewline
$oscdimgPath = Get-PackerIsoToolPath
if (-not $oscdimgPath) {
    $adkSetupPath = 'D:\LabSources\SoftwarePackages\ADK\adksetup.exe'
    if (-not (Test-Path -LiteralPath $adkSetupPath -PathType Leaf)) {
        Write-Host " MISSING" -ForegroundColor Red
        throw "oscdimg.exe is missing and the ADK offline installer was not found at $adkSetupPath. Run .\Populate-LabSources.ps1 first."
    }

    Write-Host " Installing ADK Deployment Tools..." -ForegroundColor Yellow
    $installer = Start-Process -FilePath $adkSetupPath `
        -ArgumentList '/quiet /norestart /features OptionId.DeploymentTools' `
        -Wait -PassThru
    if ($installer.ExitCode -notin @(0, 3010, 1638)) {
        throw "ADK Deployment Tools installation failed with exit code $($installer.ExitCode)."
    }

    $oscdimgPath = Get-PackerIsoToolPath
    if (-not $oscdimgPath) {
        if ($installer.ExitCode -eq 3010) {
            throw 'ADK installation requires a restart. Restart Windows, then rerun .\Setup-Packer.ps1.'
        }
        throw 'ADK installer completed, but oscdimg.exe was not found in the standard Deployment Tools locations.'
    }
    Write-Host " OK ($oscdimgPath)" -ForegroundColor Green
} else {
    Write-Host " OK ($oscdimgPath)" -ForegroundColor Green
}

Initialize-PackerIsoToolPath | Out-Null
Write-Host "`n=== Packer setup complete. Ready to build images. ===" -ForegroundColor Green
