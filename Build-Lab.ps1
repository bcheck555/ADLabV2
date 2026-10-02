#Requires -RunAsAdministrator
# Build-Lab.ps1 - ADLabV2 orchestrator (host-side bootstrap only)
# Runs: OpenTofu (create VMs) -> Docker Ansible (configure VMs)
#
# NOTE: This script is used for the INITIAL bootstrap only.
#   After GIT01 is up with Docker + GitLab Runner, all future runs happen
#   via GitLab CI (ansible runs in Docker on GIT01 - no host Docker needed).
#
# Prerequisites:
#   - Packer base images already built (run packer build manually for each image type)
#   - LabNAT Hyper-V switch exists (created by the ad-hyperv-lab Ansible playbook)
#   - tofu.exe in PATH
#   - Docker Desktop running (bootstrap only - GIT01 takes over after first run)
#   - AD_LAB_ADMIN_PASSWORD set in this PowerShell process
#   - For Docker to reach lab VMs: add a route manually if needed:
#       $gw = (Get-NetIPAddress -InterfaceAlias 'vEthernet (DockerNAT)' -AddressFamily IPv4).IPAddress
#       route add 192.168.100.0 MASK 255.255.255.0 $gw

[CmdletBinding()]
param(
    [switch]$SkipTofu,                # Skip OpenTofu (VMs already exist)
    [switch]$SkipNetworkBootstrap,    # Skip PowerShell Direct IP bootstrap
    [switch]$SkipAnsible,             # Skip Ansible (infrastructure only)
    [string]$AnsibleLimit = '',       # Limit Ansible to specific hosts (e.g. 'dc01')
    [string]$AnsibleTags  = '',       # Ansible tags filter (e.g. 'ad,dns')
    [switch]$GitLabOnly               # Bootstrap GIT01 only (gitlab.yml)
)

$ErrorActionPreference = 'Stop'
$LabRoot = $PSScriptRoot

function Write-Step([string]$msg) {
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

# ---Verify prerequisites ------------------------------------------------------
Write-Step 'Checking prerequisites'

$cfg = Import-PowerShellDataFile "$LabRoot\config\lab.config.psd1"
if ([string]::IsNullOrWhiteSpace($env:AD_LAB_ADMIN_PASSWORD)) {
    throw 'Set AD_LAB_ADMIN_PASSWORD in this PowerShell process before building the lab.'
}

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

# ---OpenTofu -----------------------------------------------------------------
if (-not $SkipTofu) {
    Write-Step 'Running OpenTofu (creating VMs)'
    if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 5986 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
        throw 'WinRM HTTPS is unavailable on 127.0.0.1:5986. Run .\Setup-Tofu.ps1 from an elevated PowerShell, then retry.'
    }
    Push-Location "$LabRoot\terraform"
    $previousTfPassword = [Environment]::GetEnvironmentVariable('TF_VAR_host_password', 'Process')
    $env:TF_VAR_host_password = $env:AD_LAB_ADMIN_PASSWORD
    try {
        & tofu init -input=false
        if ($LASTEXITCODE -ne 0) { throw "tofu init failed" }

        & tofu apply -input=false -auto-approve -parallelism=5
        if ($LASTEXITCODE -ne 0) { throw "tofu apply failed" }
    } finally {
        if ($null -eq $previousTfPassword) {
            Remove-Item Env:TF_VAR_host_password -ErrorAction SilentlyContinue
        } else {
            $env:TF_VAR_host_password = $previousTfPassword
        }
        Pop-Location
    }
} else {
    Write-Host 'Skipping OpenTofu (--SkipTofu).'
}

# ---Network bootstrap (PowerShell Direct) ------------------------------------
if (-not $SkipNetworkBootstrap) {
    Write-Step 'Bootstrapping VM network (PowerShell Direct)'

    # Set host vNIC for the configured lab switch to gateway IP
    $hostAdapter = Get-NetAdapter | Where-Object { $_.Name -eq "vEthernet ($($cfg.SwitchName))" }
    if ($hostAdapter) {
        $existing = Get-NetIPAddress -InterfaceIndex $hostAdapter.InterfaceIndex `
                        -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if (-not $existing -or $existing.IPAddress -ne $cfg.GatewayIP) {
            if ($existing) {
                Remove-NetIPAddress -InterfaceIndex $hostAdapter.InterfaceIndex `
                    -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            }
            New-NetIPAddress -InterfaceIndex $hostAdapter.InterfaceIndex `
                -IPAddress $cfg.GatewayIP -PrefixLength $cfg.PrefixLength | Out-Null
            Write-Host "Host vNIC set to $($cfg.GatewayIP)"
        } else {
            Write-Host "Host vNIC already $($cfg.GatewayIP)"
        }
    } else {
        Write-Warning "vEthernet ($($cfg.SwitchName)) not found - skipping host vNIC config"
    }

    $ws2025Cred = New-Object PSCredential(
        $cfg.LocalAdminUser,
        (ConvertTo-SecureString $env:AD_LAB_ADMIN_PASSWORD -AsPlainText -Force)
    )
    $win11Cred = New-Object PSCredential(
        $cfg.LocalAdminUser,   # Use Administrator for Win11 as well
        (ConvertTo-SecureString $env:AD_LAB_ADMIN_PASSWORD -AsPlainText -Force)
    )

    foreach ($vm in $cfg.VMs) {
        # PowerShell Direct only works for Windows guests
        if ($vm.ParentVHD -eq 'Ubuntu2404') {
            Write-Host "Skipping $($vm.Name) (Linux - manual bootstrap required)"
            continue
        }

        $vmState = (Get-VM -Name $vm.Name -ErrorAction SilentlyContinue).State
        if ($vmState -ne 'Running') {
            Write-Warning "$($vm.Name) is not Running (state: $vmState) - skipping"
            continue
        }

        $localCred = if ($vm.ParentVHD -eq 'Win11') { $win11Cred } else { $ws2025Cred }
        Write-Host "  $($vm.Name) -> $($vm.IP) ..." -NoNewline
        try {
            Invoke-Command -VMName $vm.Name -Credential $localCred -ErrorAction Stop -ScriptBlock {
                param($ip, $pfx, $gw, $dns1, $dns2)
                $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
                $current = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex `
                               -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                           Where-Object { $_.PrefixOrigin -ne 'WellKnown' }

                if ($current -and $current.IPAddress -eq $ip) {
                    Write-Host "already set"
                    return
                }

                # Clear existing config
                $current | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
                    -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

                New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
                    -IPAddress $ip -PrefixLength $pfx -DefaultGateway $gw | Out-Null
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                    -ServerAddresses $dns1, $dns2
            } -ArgumentList $vm.IP, $cfg.PrefixLength, $cfg.GatewayIP, $cfg.DnsServer1, $cfg.DnsServer2
            Write-Host ' done'
        } catch {
            Write-Warning "$($vm.Name) PowerShell Direct failed: $_"
        }
    }
} else {
    Write-Host 'Skipping network bootstrap (--SkipNetworkBootstrap).'
}

# ---Ansible (Docker) ----------------------------------------------------------
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
    if (-not $GitLabOnly) {
        Write-Warning "Running site.yml from Windows. Intended workflow: use -GitLabOnly here, then run site.yml from GIT01 via GitLab CI."
    }
    Push-Location "$LabRoot\docker"
    try {
        $playbook = if ($GitLabOnly) { 'gitlab.yml' } else { 'site.yml' }

        $ansibleArgs = @('run', '--rm', 'ansible', $playbook)
        if ($AnsibleLimit) { $ansibleArgs += '--limit', $AnsibleLimit }
        if ($AnsibleTags)  { $ansibleArgs += '--tags', $AnsibleTags }

        & docker-compose @ansibleArgs
        if ($LASTEXITCODE -eq 4) {
            Write-Warning "Ansible finished with unreachable hosts (exit 4). See PLAY RECAP above for per-host status."
        } elseif ($LASTEXITCODE -eq 2) {
            # ansible-core returns 2 when hosts are rescued via meta:end_host
            # in a rescue block - the internal failure state isn't fully cleared
            # even though PLAY RECAP shows failed=0. Treat as a warning.
            Write-Warning "Ansible exited with code 2 (rescued/skipped hosts). Check PLAY RECAP - if failed=0 for all hosts, this is safe to ignore."
        } elseif ($LASTEXITCODE -ne 0) {
            throw "Ansible playbook failed with exit code $LASTEXITCODE"
        }
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
    Write-Host '  2. Push ADLabV2 repo to GIT01:'
    Write-Host '       git remote add origin http://192.168.100.5/root/ADLabV2.git && git push -u origin feature/toolchain-redesign'
    Write-Host '  3. Register GitLab Runner on GIT01 (Docker executor):'
    Write-Host '       ssh labadmin@192.168.100.5'
    Write-Host '       sudo gitlab-runner register --url http://192.168.100.5 --executor docker --docker-image alpine --tag-list git01'
    Write-Host '  4. Build the Ansible image on GIT01:'
    Write-Host '       ssh labadmin@192.168.100.5 ''cd ADLabV2; docker compose -f docker/docker-compose.yml build'''
    Write-Host '  5. Add SSH_PRIVATE_KEY CI variable in GitLab (contents of /home/labadmin/.ssh/id_ed25519 on GIT01)'
    Write-Host '  6. Future full-lab runs: trigger the ansible:deploy pipeline in GitLab CI'
} else {
    Write-Host '  - DC01 (192.168.100.10): Primary DC - lab.local forest root'
    Write-Host '  - GIT01 (192.168.100.5): GitLab CE - http://192.168.100.5'
    Write-Host '  - All VMs accessible via RDP and SSH'
}
