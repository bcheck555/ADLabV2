#Requires -RunAsAdministrator
# Build-Win11.ps1
# Runs the Win11 Packer build and enables vTPM on the Packer VM the moment
# it appears — before Windows Setup performs its TPM compatibility check.
# Packer's hyperv-iso builder has no native vTPM option, so we race it here.

param(
    [string] $PackerDir,
    [string] $VMName    = 'win11-packer-build'
)

$ErrorActionPreference = 'Stop'
$LabRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Import-PowerShellDataFile "$LabRoot\config\lab.config.psd1"

if (-not $PackerDir) { $PackerDir = Join-Path $cfg.PackerDir 'win11' }
$OutputDir = Join-Path $PackerDir 'output'

# Add packer tools to PATH for oscdimg
$packerToolDir = Split-Path -Parent $cfg.PackerExe
$env:PATH = "$packerToolDir;$env:PATH"

Write-Host "=== Build-Win11: Starting Packer build ===" -ForegroundColor Cyan
Write-Host "This will take 30-60 minutes" -ForegroundColor Yellow

Push-Location $PackerDir
try {
    & packer init .
    if ($LASTEXITCODE -ne 0) { throw "packer init failed" }
} finally {
    Pop-Location
}

# Start Packer as a background process so we can enable vTPM in parallel
$packerLog  = Join-Path $env:TEMP 'packer-win11.log'
$packerNul  = Join-Path $env:TEMP 'packer-win11.nul'
# Create an empty file for stdin so Start-Process doesn't close the handle (causes EOF)
[IO.File]::WriteAllText($packerNul, '')
$packerArgs = "build -var `"iso_path=$($cfg.Win11ISO)`" -var `"output_dir=$OutputDir`" -var `"switch_name=$($cfg.PackerSwitch)`" -var `"ssh_pass=$($cfg.LocalAdminPass)`" `"$PackerDir`""
$packer = Start-Process -FilePath 'packer' `
                        -ArgumentList $packerArgs `
                        -PassThru `
                        -RedirectStandardInput  $packerNul `
                        -RedirectStandardOutput $packerLog `
                        -RedirectStandardError  "$packerLog.err" `
                        -NoNewWindow

Write-Host "  Packer PID: $($packer.Id)"
Write-Host "  Polling for VM '$VMName' to appear so we can enable vTPM..."

# Poll until Packer creates the VM (usually within 10-20s)
$deadline = (Get-Date).AddMinutes(5)
$vtpmEnabled = $false

while ((Get-Date) -lt $deadline) {
    if ($packer.HasExited) {
        Write-Host "  Packer exited before vTPM could be enabled (exit: $($packer.ExitCode))."
        break
    }

    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($vm) {
        Write-Host "  VM '$VMName' found. Enabling vTPM..."
        try {
            Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
            Enable-VMTPM        -VMName $VMName
            $vtpmEnabled = $true
            Write-Host "  vTPM enabled on '$VMName'." -ForegroundColor Green
        } catch {
            Write-Warning "  Failed to enable vTPM: $_"
        }
        break
    }

    Start-Sleep -Milliseconds 500
}

if (-not $vtpmEnabled -and -not $packer.HasExited) {
    Write-Warning "  vTPM not enabled within 5 minutes — TPM check may fail."
}

# Stream Packer output to console while waiting
Write-Host "  Waiting for Packer to complete..."
$lastPos = 0
while (-not $packer.HasExited) {
    Start-Sleep -Seconds 5
    $content = Get-Content $packerLog -ErrorAction SilentlyContinue
    if ($content -and $content.Count -gt $lastPos) {
        $content[$lastPos..($content.Count - 1)] | ForEach-Object { Write-Host "  [packer] $_" }
        $lastPos = $content.Count
    }
}

# Flush remaining output
$content = Get-Content $packerLog -ErrorAction SilentlyContinue
if ($content -and $content.Count -gt $lastPos) {
    $content[$lastPos..($content.Count - 1)] | ForEach-Object { Write-Host "  [packer] $_" }
}

if ($packer.ExitCode -ne 0) {
    $errContent = Get-Content "$packerLog.err" -ErrorAction SilentlyContinue
    if ($errContent) { $errContent | ForEach-Object { Write-Warning $_ } }
    throw "Packer Win11 build failed with exit code $($packer.ExitCode). See $packerLog"
}

Write-Host "=== Build-Win11: Complete ===" -ForegroundColor Green
