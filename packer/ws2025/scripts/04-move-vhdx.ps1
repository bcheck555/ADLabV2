#Requires -RunAsAdministrator
# Packer post-processor: 04-move-vhdx.ps1
# Moves the built VHDX from packer output dir to base-vhds

param(
    [string]$OutputDir,
    [string]$DestPath
)

$ErrorActionPreference = 'Stop'

Write-Host "Moving VHDX from $OutputDir to $DestPath..."

$src = Get-ChildItem $OutputDir -Filter '*.vhdx' -Recurse | Select-Object -First 1
if (-not $src) {
    Write-Error "No VHDX found in output directory: $OutputDir"
    exit 1
}

$destDir = Split-Path $DestPath
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
Move-Item $src.FullName $DestPath -Force
Write-Host "Moved $($src.Name) to $DestPath"

Remove-Item $OutputDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Cleaned up output directory"
