# ADLabV2

Active Directory lab rebuilt with **Packer + OpenTofu + Ansible**.

| Tool | Purpose |
|------|---------|
| Packer | Build reusable base VM images (WS2025, Win11, Ubuntu 24.04) |
| OpenTofu | Create / destroy Hyper-V VMs from base images |
| Ansible | Configure VMs (AD, CA, SQL, IIS, GitLab, etc.) |
| GitLab CE | CI/CD once bootstrapped — running on GIT01 in the lab |

## VM Inventory

| Host | IP | OS | Role |
|------|----|----|------|
| GIT01 | 192.168.100.5 | Ubuntu 24.04 | GitLab CE (control plane) |
| DC01 | 192.168.100.10 | WS2025 | Primary DC, DNS |
| DC02 | 192.168.100.11 | WS2025 | Secondary DC |
| CA01 | 192.168.100.20 | WS2025 | Enterprise Root CA |
| DB01 | 192.168.100.30 | WS2025 | SQL Server 2022 |
| WEB01 | 192.168.100.40 | WS2025 | IIS |
| WKS01 | 192.168.100.50 | Win11 | Workstation |
| WKS02 | 192.168.100.51 | Win11 | Workstation |
| VMM01 | 192.168.100.60 | WS2025 | SCVMM 2025 |

## Transport: SSH (not WinRM)

All VMs use **OpenSSH** for Ansible connectivity. Packer installs OpenSSH Server + PowerShell 7 during image build. This survives future DISA STIG GPO hardening (WinRM is frequently disabled or heavily restricted by STIGs; SSH is not).

## Quick Start

### 1. Prerequisites

```powershell
# Create the LabSwitch (one-time)
New-VMSwitch -Name LabSwitch -SwitchType Internal

# Configure NAT for lab internet access (optional)
New-NetNat -Name LabNAT -InternalIPInterfaceAddressPrefix 192.168.100.0/24

# Download ISOs to D:\LabSources\ISOs\
# See config/lab.config.psd1 for expected filenames
```

### 2. Build Packer Images

```powershell
# Ubuntu (for GIT01) — build this first
packer init packer\ubuntu2404\
packer build packer\ubuntu2404\

# WS2025 (for all Windows servers)
packer init packer\ws2025\
packer build packer\ws2025\

# Win11 (for workstations)
packer init packer\win11\
packer build packer\win11\
```

### 3. Configure OpenTofu

Edit `terraform/terraform.tfvars`:
```hcl
host_user     = "Administrator"
host_password = "your-host-password"
```

### 4. Bootstrap: Manual First Run

```powershell
# Phase 1: Create all VMs
.\Build-Lab.ps1 -SkipAnsible

# Phase 2a: Bootstrap GitLab first (standalone)
.\Build-Lab.ps1 -SkipTofu -GitLabOnly

# Phase 2b: Configure full lab
.\Build-Lab.ps1 -SkipTofu
```

### 5. Set Up GitLab CI (one-time)

After GIT01 is up:
1. Browse to `http://192.168.100.5` — log in as `root`
2. Push this repo: `git remote add origin http://192.168.100.5/root/ADLabV2.git && git push -u origin feature/toolchain-redesign`
3. Install GitLab Runner on the Hyper-V host:
   ```powershell
   # Download gitlab-runner.exe for Windows and register:
   gitlab-runner register --url http://192.168.100.5 --executor shell --shell powershell
   ```
4. Future rebuilds: trigger the pipeline from GitLab UI

## Network Routing (Docker → Lab VMs)

Docker Desktop on Windows doesn't support `network_mode: host`. To let the Ansible container reach lab VMs:

```powershell
# Find Docker bridge gateway (run after Docker Desktop starts)
$dockerGW = (Get-NetIPAddress -InterfaceAlias 'vEthernet (DockerNAT)' -AddressFamily IPv4).IPAddress

# Add route (temporary — reset on reboot)
route add 192.168.100.0 MASK 255.255.255.0 $dockerGW

# Or use Build-Lab.ps1 which handles this automatically
```

## Ansible Usage

```powershell
# Build the Ansible container
docker-compose -f docker\docker-compose.yml build

# Ping all hosts
docker-compose -f docker\docker-compose.yml run --entrypoint ansible ansible all -m ping

# Full playbook
docker-compose -f docker\docker-compose.yml run ansible ansible-playbook site.yml

# Single host
docker-compose -f docker\docker-compose.yml run ansible ansible-playbook site.yml --limit dc01

# With tags
docker-compose -f docker\docker-compose.yml run ansible ansible-playbook site.yml --tags ad
```

## Destroy

```powershell
.\Destroy-Lab.ps1
# Base VHDs are preserved — next rebuild skips Packer
```

## GitLab Migration

To migrate an existing GitLab instance to GIT01:

```bash
# On old server:
sudo gitlab-backup create

# Copy backup + secrets to GIT01
scp /var/opt/gitlab/backups/<timestamp>_gitlab_backup.tar labadmin@192.168.100.5:/tmp/
scp /etc/gitlab/gitlab-secrets.json labadmin@192.168.100.5:/tmp/

# On GIT01 (after Ansible configures it):
sudo cp /tmp/*_gitlab_backup.tar /var/opt/gitlab/backups/
sudo chown git:git /var/opt/gitlab/backups/*_gitlab_backup.tar
sudo cp /tmp/gitlab-secrets.json /etc/gitlab/gitlab-secrets.json
sudo gitlab-ctl stop puma
sudo gitlab-ctl stop sidekiq
sudo gitlab-backup restore BACKUP=<timestamp>
sudo gitlab-ctl reconfigure
sudo gitlab-ctl start
```
