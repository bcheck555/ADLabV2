#requires -Version 5.1
<#
.SYNOPSIS
Creates GIT01's cloud-init NoCloud ISO from the lab network configuration.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$ConfigPath = "$PSScriptRoot\config\lab.config.psd1"
)

$ErrorActionPreference = 'Stop'
$cfg = Import-PowerShellDataFile -LiteralPath $ConfigPath
$git01 = @($cfg.VMs | Where-Object { $_.Name -eq 'GIT01' })
if ($git01.Count -ne 1) { throw 'Config must contain exactly one GIT01 VM.' }
foreach ($value in @($git01[0].IP, $cfg.GatewayIP, $cfg.DnsServer1, $cfg.DnsServer2)) {
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse([string]$value, [ref]$address) -or
        $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Invalid IPv4 address in lab config: $value"
    }
}
$prefix = [int]$cfg.PrefixLength
if ($prefix -lt 1 -or $prefix -gt 32) { throw 'PrefixLength must be between 1 and 32.' }

# OpenTofu uses a versioned path; never overwrite an ISO attached to a VM.
if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
    if ((Get-Item -LiteralPath $OutputPath).Length -eq 0) { throw "Empty seed ISO: $OutputPath" }
    Write-Host "Using existing GIT01 seed: $OutputPath"
    return
}
. "$PSScriptRoot\Packer-HostTools.ps1"
$isoTool = Initialize-PackerIsoToolPath
$output = [System.IO.Path]::GetFullPath($OutputPath)
$parent = Split-Path -Parent $output
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$temporary = Join-Path $parent ('.git01-seed-' + [guid]::NewGuid().ToString('N'))
$stagingIso = "$temporary.iso"
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $instanceId = 'git01-' + [System.IO.Path]::GetFileNameWithoutExtension($output)
    $metadata = "instance-id: $instanceId`nlocal-hostname: git01`n"
    # Keep the labadmin account/password already installed by Packer.
    $userdata = "#cloud-config`npreserve_hostname: false`nusers: []`nssh_pwauth: true`n"
    $network = @"
version: 2
ethernets:
  eth0:
    match:
      name: "e*"
    set-name: eth0
    dhcp4: false
    addresses:
      - $($git01[0].IP)/$prefix
    routes:
      - to: default
        via: $($cfg.GatewayIP)
    nameservers:
      addresses:
        - $($cfg.DnsServer1)
        - $($cfg.DnsServer2)
        - 8.8.8.8
"@
    [System.IO.File]::WriteAllText((Join-Path $temporary 'meta-data'), $metadata, $encoding)
    [System.IO.File]::WriteAllText((Join-Path $temporary 'user-data'), $userdata, $encoding)
    [System.IO.File]::WriteAllText((Join-Path $temporary 'network-config'), "$network`n", $encoding)
    & $isoTool -j2 -lCIDATA -m $temporary $stagingIso
    if ($LASTEXITCODE -ne 0) { throw "oscdimg failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $stagingIso -PathType Leaf)) { throw 'oscdimg did not create the seed ISO.' }
    Move-Item -LiteralPath $stagingIso -Destination $output
    Write-Host "Created GIT01 seed: $output ($($git01[0].IP)/$prefix)"
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stagingIso -Force -ErrorAction SilentlyContinue
}
