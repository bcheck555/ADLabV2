#Requires -RunAsAdministrator
# Build-Lab.ps1 — ADLabV2 orchestrator
# Runs: OpenTofu (create VMs) → Docker Ansible (configure VMs)
#
# Prerequisites:
#   - Packer base images already built (run packer build manually for each image type)
#   - LabSwitch Hyper-V switch exists (run New-VMSwitch -Name LabSwitch -SwitchType Internal first)
#   - tofu.exe in PATH (or set $TofuExe below)
#   - Docker Desktop running
#   - terraform/terraform.tfvars populated with host_password

[CmdletBinding()]
param(
    [switch]$SkipTofu,           # Skip OpenTofu (VMs already exist)
    [switch]$SkipAnsible,        # Skip Ansible (infrastructure only)
    [string]$AnsibleLimit = '',  # Limit Ansible to specific hosts (e.g. 'dc01')
    [string]$AnsibleTags  = '',  # Ansible tags filter (e.g. 'ad,dns')
    [switch]$GitLabOnly          # Bootstrap GIT01 only (gitlab.yml)
)

$ErrorActionPreference = 'Stop'
$LabRoot = $PSScriptRoot

function Write-Step([string]$msg) {
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

# ── Verify prerequisites ──────────────────────────────────────────────────────
Write-Step 'Checking prerequisites'

$cfg = Import-PowerShellDataFile "$LabRoot\config\lab.config.psd1"

foreach ($vhd in @($cfg.WS2025BaseVHD, $cfg.Win11BaseVHD, $cfg.Ubuntu2404BaseVHD)) {
    if (-not (Test-Path $vhd)) {
        Write-Warning "Base VHD not found: $vhd"
        Write-Warning "Run the corresponding packer build first. Skipping VHD check."
    }
}

$switch = Get-VMSwitch -Name $cfg.SwitchName -ErrorAction SilentlyContinue
if (-not $switch) {
    throw "Hyper-V switch '$($cfg.SwitchName)' not found. Run: New-VMSwitch -Name '$($cfg.SwitchName)' -SwitchType Internal"
}

# ── Docker network routing ────────────────────────────────────────────────────
Write-Step 'Configuring Docker → LabSwitch routing'
try {
    $dockerGW = (Get-NetIPAddress -InterfaceAlias 'vEthernet (DockerNAT)' -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if (-not $dockerGW) {
        $dockerGW = (Get-NetIPAddress -InterfaceAlias 'vEthernet (nat)' -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    }
    if ($dockerGW) {
        $existingRoute = Get-NetRoute -DestinationPrefix '192.168.100.0/24' -ErrorAction SilentlyContinue
        if (-not $existingRoute) {
            New-NetRoute -DestinationPrefix '192.168.100.0/24' -InterfaceAlias $cfg.SwitchName -NextHop $dockerGW -ErrorAction SilentlyContinue
            Write-Host "Added route: 192.168.100.0/24 via $dockerGW"
        } else {
            Write-Host "Route already exists."
        }
    } else {
        Write-Warning "Docker NAT interface not found. Containers may not reach lab VMs."
        Write-Warning "Manually add: route add 192.168.100.0 MASK 255.255.255.0 <docker-bridge-ip>"
    }
} catch {
    Write-Warning "Could not configure Docker routing: $_"
}

# ── OpenTofu ──────────────────────────────────────────────────────────────────
if (-not $SkipTofu) {
    Write-Step 'Running OpenTofu (creating VMs)'
    Push-Location "$LabRoot\terraform"
    try {
        & tofu init -input=false
        if ($LASTEXITCODE -ne 0) { throw "tofu init failed" }
        & tofu apply -input=false -auto-approve
        if ($LASTEXITCODE -ne 0) { throw "tofu apply failed" }
    } finally {
        Pop-Location
    }
    Write-Host 'Waiting 30s for VMs to start booting...'
    Start-Sleep -Seconds 30
} else {
    Write-Host 'Skipping OpenTofu (--SkipTofu).'
}

# ── Ansible (Docker) ──────────────────────────────────────────────────────────
if (-not $SkipAnsible) {
    Write-Step 'Building Ansible Docker image'
    Push-Location "$LabRoot\docker"
    try {
        & docker-compose build
        if ($LASTEXITCODE -ne 0) { throw "docker-compose build failed" }
    } finally {
        Pop-Location
    }

    Write-Step 'Running Ansible playbook'
    Push-Location "$LabRoot\docker"
    try {
        $playbook = if ($GitLabOnly) { 'gitlab.yml' } else { 'site.yml' }

        $ansibleArgs = @('run', '--rm', 'ansible', 'ansible-playbook', $playbook)
        if ($AnsibleLimit) { $ansibleArgs += '--limit', $AnsibleLimit }
        if ($AnsibleTags)  { $ansibleArgs += '--tags', $AnsibleTags }

        & docker-compose @ansibleArgs
        if ($LASTEXITCODE -ne 0) { throw "Ansible playbook failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
} else {
    Write-Host 'Skipping Ansible (--SkipAnsible).'
}

Write-Step 'Build-Lab complete'
Write-Host ''
Write-Host 'Next steps:'
if ($GitLabOnly) {
    Write-Host '  1. Browse to http://192.168.100.5 and log in as root'
    Write-Host '  2. Push ADLabV2 repo: git remote add origin http://192.168.100.5/root/ADLabV2.git'
    Write-Host '  3. Install GitLab Runner on this host and register it'
    Write-Host '  4. Run Build-Lab.ps1 again (without -GitLabOnly) to configure the full lab'
} else {
    Write-Host '  - DC01 (192.168.100.10): Primary DC — lab.local forest root'
    Write-Host '  - GIT01 (192.168.100.5): GitLab CE — http://192.168.100.5'
    Write-Host '  - All VMs accessible via RDP and SSH'
}
