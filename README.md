# ADLabV2

Active Directory lab built with **Packer + OpenTofu + Ansible**.

| Tool | Purpose |
|------|---------|
| Packer | Build reusable base VM images (WS2025, Win11, Ubuntu 24.04) |
| OpenTofu | Create / destroy Hyper-V VMs from those base images |
| Ansible | Configure VMs (AD, CA, SQL, IIS, GitLab, SCVMM) |
| GitLab CE | CI/CD — running on GIT01 (Ubuntu 24.04, 192.168.100.5) |
| Docker CE | Ansible control-node container — runs on GIT01, not host Docker Desktop |

## VM Inventory

| Host | IP | OS | Role | Local admin user |
|------|----|----|------|------------------|
| GIT01 | 192.168.100.5 | Ubuntu 24.04 | GitLab CE + Ansible control node | `labadmin` |
| DC01 | 192.168.100.10 | WS2025 | Primary DC, DNS, forest root | `Administrator` |
| DC02 | 192.168.100.11 | WS2025 | Secondary DC | `Administrator` |
| CA01 | 192.168.100.20 | WS2025 | Enterprise Root CA | `Administrator` |
| DB01 | 192.168.100.30 | WS2025 | SQL Server Developer Edition (32 GB RAM, 8 vCPU) | `Administrator` |
| WEB01 | 192.168.100.40 | WS2025 | IIS | `Administrator` |
| WKS01 | 192.168.100.50 | Win11 | Workstation | `labadmin` |
| WKS02 | 192.168.100.51 | Win11 | Workstation | `labadmin` |
| VMM01 | 192.168.100.60 | WS2025 | SCVMM 2025 (nested virt enabled) | `Administrator` |

## Transport: SSH everywhere (not WinRM)

All VMs **and the Hyper-V host itself** use **OpenSSH** for Ansible connectivity.

- Packer bakes OpenSSH Server + PowerShell 7 into every Windows image during build.
- `group_vars/windows.yml` sets `ansible_connection: ssh` + `ansible_shell_type: powershell` for all Windows VMs.
- `group_vars/hyperv.yml` sets the same for `hvhost` — the physical Hyper-V host. Ansible delegates tasks that require the Hyper-V API (e.g. mounting/unmounting ISOs via `Set-VMDvdDrive`) to `hvhost` over SSH using `ansible.builtin.shell`.
- SSH is resilient to DISA STIG GPO hardening that frequently disables or restricts WinRM.

> **Important:** `ansible.windows.win_powershell` (WinRM module) must **not** be used for tasks delegated to `hvhost`. Use `ansible.builtin.shell` instead — it runs PowerShell via the SSH shell, no WinRM exec-wrapper required.

## Ansible Control Node Architecture

Ansible runs inside a Docker container **on GIT01**, not on the Hyper-V host. This means:

- No Docker Desktop routing workarounds — GIT01 is on LabNAT and reaches all lab VMs directly.
- GitLab Runner uses the **Docker executor** — CI jobs run in isolated containers.
- `network_mode: host` in `docker/docker-compose.yml` works correctly on Linux.
- Host Docker Desktop is only needed for the initial GIT01 bootstrap.

---

## Quick Start

### 1. Prerequisites

#### Software (on the Hyper-V host)

| Tool | Minimum version | Notes |
|------|----------------|-------|
| Packer | 1.9.0 | `packer.exe` in `PATH` or set `PackerExe` in `config/lab.config.psd1` |
| OpenTofu | latest stable | `tofu.exe` in `PATH` or set `TofuExe` in `config/lab.config.psd1` |
| Docker Desktop | latest | Bootstrap only — GIT01 takes over after first run |
| **OpenSSH Server** | **Windows optional feature** | **Required — Ansible delegates Hyper-V tasks to the host over SSH. Install via:** `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0` then `Start-Service sshd; Set-Service sshd -StartupType Automatic` |

#### One-time Hyper-V setup

```powershell
# Create the internal switch used by all lab VMs
# LabNAT is created and configured by the ad-hyperv-lab Ansible playbook.
Get-VMSwitch -Name LabNAT

# Optional: NAT for lab internet access
New-NetNat -Name LabNAT -InternalIPInterfaceAddressPrefix 192.168.100.0/24
```

#### Required file layout on the Hyper-V host

All software is staged on the Hyper-V host. Ansible mounts ISOs via Hyper-V DVD drives and
stages installer files over SMB — no manual copying into VMs is needed.

```
D:\LabSources\
├── ISOs\
│   ├── Windows_Server_2025_EVAL_x64FRE_en-us.iso
│   ├── Windows_11_Enterprise_EVAL_x64_en-us.iso
│   └── ubuntu-24.04.4-live-server-amd64.iso
│
└── SoftwarePackages\
    ├── SQLServer2022-DEV-x64-ENU.iso
    ├── OpenSSH-Win64-v10.0.0.0.msi
    ├── PowerShell-7.6.6-win-x64.msi
    ├── msodbcsql.msi
    ├── MsSqlCmdLnUtils.msi
    ├── ADK\
    │   └── adksetup.exe
    ├── ADKWinPE\
    │   └── adkwinpesetup.exe
    └── SCVMM2025\
        ├── setup.exe
        └── Prerequisites\
```

**ISO and package paths** are configured in `ansible/group_vars/all.yml` (`sql_iso_host_path`) and
`config/lab.config.psd1` (Packer ISO paths). The SCVMM role requires `setup.exe`
directly under `SoftwarePackages\SCVMM2025`.

Populate and validate the complete tree from an elevated Windows PowerShell prompt:

```powershell
.\Populate-LabSources.ps1

# Validate existing media without downloading anything
.\Populate-LabSources.ps1 -ValidateOnly
```

Use `-WindowsServerIsoPath`, `-Windows11IsoPath`, `-SqlServerIsoPath`, or
`-ScvmmMediaPath` to supply locally downloaded or licensed media. Downloads are resumable,
and existing verified files are preserved unless `-Force` is specified. The script writes
`SHA256SUMS.txt`, `INVENTORY.txt`, and `LabSources.inventory.json` under
`D:\LabSources`.

Microsoft requires interactive registration for the Windows 11 Enterprise evaluation. Download
that ISO from the Evaluation Center first and pass it with `-Windows11IsoPath`; subsequent
runs reuse the staged, validated ISO without requiring the parameter.

Microsoft has retired the public SQL Server 2022 web bootstrapper. Obtain a SQL Server 2022
Developer ISO from an authorized Microsoft download channel and pass it with
`-SqlServerIsoPath`. Once staged as `SoftwarePackages\SQLServer2022-DEV-x64-ENU.iso`,
subsequent runs reuse it without requiring the parameter.

**Creating the ADK offline layout** (run once on any internet-connected machine, then copy to the host):

```powershell
.\adksetup.exe /layout D:\LabSources\SoftwarePackages\ADK /quiet
.\adkwinpesetup.exe /layout D:\LabSources\SoftwarePackages\ADKWinPE /quiet
```

#### OpenTofu variables

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` for the non-secret host settings. Supply the shared password through the current PowerShell process environment:

```powershell
$secureLabPassword = Read-Host "Shared lab password" -AsSecureString
$env:AD_LAB_ADMIN_PASSWORD = [System.Net.NetworkCredential]::new('', $secureLabPassword).Password
Remove-Variable secureLabPassword
```

The checked-in example matches the host built by `ad-hyperv-lab`: the repository is
`D:\Git\ADLabV2`, VM disks and base images live below
`E:\Hyper-V\Virtual Hard Disks\ADLabV2`, and the shared switch is `LabNAT`.
Set the rotated password on the Hyper-V host and lab accounts. `Build-Lab.ps1` forwards it to OpenTofu as `TF_VAR_host_password`, and the Packer wrappers forward it as `PKR_VAR_ssh_pass`. Ansible reads `AD_LAB_ADMIN_PASSWORD` inside its container. Direct OpenTofu and Packer runs require their corresponding `TF_VAR_host_password` or `PKR_VAR_ssh_pass` environment variable.
After the build session, clear the shared variable with `Remove-Item Env:AD_LAB_ADMIN_PASSWORD -ErrorAction SilentlyContinue`.

---

### 2. Build Packer Images

Each image only needs to be built once. Packer outputs its `.vhdx` to
`E:\Hyper-V\Virtual Hard Disks\ADLabV2\Base Images`.

After `Populate-LabSources.ps1` has staged the ADK offline layout, run the Packer
setup script once from an elevated PowerShell on the Hyper-V host:

```powershell
.\Setup-Packer.ps1
```

This creates the Packer switch, checks the installer ISOs, and installs the ADK
Deployment Tools component when `oscdimg.exe` is missing. The image build wrappers
and Hyper-V CI jobs add the installed `oscdimg` directory to their process `PATH`;
they stop with setup instructions if the command cannot be found. No machine-wide
`PATH` change is made.

```powershell
# Ubuntu 24.04 (GIT01) — build first
.\Build-Ubuntu.ps1

# Windows Server 2025 (all Windows servers)
.\Build-WS2025.ps1

# Windows 11 (workstations)
.\Build-Win11.ps1
```

Convenience wrapper scripts are also available at the repo root:
`Build-Ubuntu.ps1`, `Build-WS2025.ps1`, `Build-Win11.ps1`

---

### 3. Bootstrap: Manual First Run

```powershell
# Phase 1 — Create all VMs (Ansible skipped, network bootstrapped via PowerShell Direct)
.\Build-Lab.ps1 -SkipAnsible

# Phase 2 — Bootstrap GIT01: installs Docker CE, GitLab CE, GitLab Runner,
#            and distributes GIT01's SSH public key to all other lab VMs.
#            Uses Docker Desktop on the host — last time it's needed.
.\Build-Lab.ps1 -SkipTofu -GitLabOnly

# Phase 3 — Configure domain infrastructure from the host as a one-off,
#            or skip this and let GitLab CI handle it after Phase 5.
.\Build-Lab.ps1 -SkipTofu
```

> **Note:** `site.yml` configures domain infrastructure only (DC01 through VMM01).
> GIT01 is managed exclusively via `gitlab.yml` (used by the `-GitLabOnly` flag).

---

### 4. GitLab CI Setup (one-time, after Phase 2)

Two runners are required:

| Runner tag | Executor | Host | Used for |
|------------|----------|------|---------|
| `hyperv-host` | Shell (PowerShell) | Hyper-V host | Packer image builds, OpenTofu apply/destroy |
| `git01` | Docker | GIT01 | All Ansible playbooks |

```powershell
# Push the repo to GIT01's GitLab
git remote add origin http://192.168.100.5/root/ADLabV2.git
git push -u origin main
```

SSH into GIT01 to register the runners and build the Ansible image:

```bash
ssh labadmin@192.168.100.5

# Register the git01 Docker runner
sudo gitlab-runner register \
  --url http://192.168.100.5 \
  --executor docker \
  --docker-image alpine:latest \
  --docker-network-mode host \
  --tag-list git01 \
  --non-interactive \
  --registration-token <token-from-gitlab-ui>

# Build the Ansible Docker image
cd ~/ADLabV2
docker compose -f docker/docker-compose.yml build
```

Register the `hyperv-host` Shell runner on the Hyper-V host (one-time):

```powershell
# On the Hyper-V host (PowerShell as Administrator)
gitlab-runner register `
  --url http://192.168.100.5 `
  --executor shell `
  --shell powershell `
  --tag-list hyperv-host `
  --non-interactive `
  --registration-token <token-from-gitlab-ui>
```

Install the local secret check from the repository root on each developer machine:

```powershell
py -m pip install pre-commit
pre-commit install
```

The Gitleaks pre-commit hook scans staged changes and blocks commits containing
detected secrets. GitLab CI also scans the checked-out files on every pipeline;
it does not scan old Git history. For a finding, remove the literal and source
the value from an environment or CI secret variable instead. Do not add real
credentials to the Gitleaks allowlist.

Add these CI/CD variables in GitLab (**Settings → CI/CD → Variables**):

| Variable | Type | Value |
|----------|------|-------|
| `AD_LAB_ADMIN_PASSWORD` | Masked, protected | Shared Hyper-V host and lab account password |
| `SSH_PRIVATE_KEY` | Masked file | Contents of `/home/labadmin/.ssh/id_ed25519` on GIT01 |

Packer and OpenTofu jobs map this variable to their native environment names. Ansible reads it directly; no password is added to its command line.

```bash
# On GIT01 — copy the private key value for the CI variable:
cat /home/labadmin/.ssh/id_ed25519
```

---

### 5. Run the Full Lab via CI

After both runners are registered, trigger the pipeline from the GitLab UI:

- **`ansible:deploy`** — configures all lab VMs (DC, CA, SQL, IIS, workstations, SCVMM)
- **`ansible:deploy-limit`** — set `ANSIBLE_LIMIT=db01` and/or `ANSIBLE_TAGS=sql` to target a single VM or role
- **`ansible:ping`** — reachability check across all inventory hosts
- **`terraform:plan`** — runs automatically on MR and default branch pushes
- **`terraform:apply`** / **`terraform:destroy`** — manual triggers only
- **`packer:ws2025`** / **`packer:win11`** / **`packer:ubuntu2404`** — manual triggers, rebuild base images

```powershell
# Manual fallback (from the Hyper-V host, if CI is unavailable):
.\Build-Lab.ps1 -SkipTofu
```

---

## Ansible Usage (from GIT01)

```bash
ssh labadmin@192.168.100.5
cd ~/ADLabV2

# Ping all hosts
docker compose -f docker/docker-compose.yml run --entrypoint ansible ansible \
  all -m ping

# Full site playbook
docker compose -f docker/docker-compose.yml run ansible ansible-playbook site.yml

# Single host
docker compose -f docker/docker-compose.yml run ansible ansible-playbook site.yml --limit db01

# With tags
docker compose -f docker/docker-compose.yml run ansible ansible-playbook site.yml --tags sql

# Distribute GIT01 SSH key to all VMs (after re-provisioning GIT01)
docker compose -f docker/docker-compose.yml run ansible ansible-playbook gitlab.yml --tags ssh_keys
```

The Ansible image is built from `docker/Dockerfile` using `python:3.12-slim`,
`ansible-core==2.17.*`, and the following Galaxy collections:

| Collection | Purpose |
|------------|---------|
| `ansible.windows` ≥ 2.3.0 | Core Windows modules (`win_powershell`, `win_feature`, etc.) |
| `community.windows` ≥ 2.2.0 | Supplemental Windows modules (`win_firewall_rule`, etc.) |
| `ansible.posix` ≥ 1.5.0 | Linux/POSIX modules (GIT01) |
| `microsoft.ad` ≥ 1.3.0 | Active Directory modules (`microsoft.ad.user`, `microsoft.ad.ou`) |

---

## Playbook Structure

`site.yml` runs in two stages:

1. **DC01** — Promotes the forest root (`lab.local`), creates all OUs, users, and DNS zones. Must complete before anything else joins the domain.
2. **DC02, CA01, DB01, WEB01, WKS01, WKS02** — Configured in parallel (`strategy: free`). Each host runs `common_windows` first (static IP + hostname), then its role-specific tasks.
3. **VMM01** — Configured last; depends on the domain (DC01) and SQL Server (DB01) both being ready.

`gitlab.yml` manages GIT01 independently and is never included in `site.yml`.

---

## AD OU Structure

```
DC=lab,DC=local
└── OU=NETS
    ├── OU=Computers
    │   ├── OU=Servers       — CA01, DB01, WEB01, VMM01, DC02
    │   └── OU=Workstations  — WKS01, WKS02
    └── OU=Users
        ├── OU=Admins
        ├── OU=Cattle        — Standard users: jsmith, mjones, bwilson
        ├── OU=Service       — Service accounts: svc_vmm
        └── OU=Security
```

---

## Destroy

```powershell
# Tears down all VMs and deletes their VHDXs. Base images in E:\Hyper-V are preserved.
.\Destroy-Lab.ps1

# Or via CI (manual trigger):
# terraform:destroy job in GitLab
```

---

## GitLab Migration

To migrate an existing GitLab instance to GIT01:

```bash
# On old server:
sudo gitlab-backup create

# Copy backup + secrets to GIT01
scp /var/opt/gitlab/backups/<timestamp>_gitlab_backup.tar labadmin@192.168.100.5:/tmp/
scp /etc/gitlab/gitlab-secrets.json labadmin@192.168.100.5:/tmp/

# On GIT01 (after Ansible has configured it):
sudo cp /tmp/*_gitlab_backup.tar /var/opt/gitlab/backups/
sudo chown git:git /var/opt/gitlab/backups/*_gitlab_backup.tar
sudo cp /tmp/gitlab-secrets.json /etc/gitlab/gitlab-secrets.json
sudo gitlab-ctl stop puma
sudo gitlab-ctl stop sidekiq
sudo gitlab-backup restore BACKUP=<timestamp>
sudo gitlab-ctl reconfigure
sudo gitlab-ctl start
```

---

## Known Issues / TODO

### Security

- Lab passwords are supplied through `AD_LAB_ADMIN_PASSWORD` at runtime. Rotate the shared password on the host and lab accounts after removing older copies from the current files.
- **Clean up WinRM remnants** in `packer/ws2025/scripts/03-sysprep.ps1` before generalize — Basic auth + unencrypted transport persist into every VM image built from it.
- **Populate `known_hosts`** after initial bootstrap and remove `StrictHostKeyChecking=no` from `group_vars/windows.yml` and `group_vars/hyperv.yml`.

### Reliability / Correctness

- **Domain join duplicated across 5 roles** — `certificate_authority`, `sql_server`, `iis`, `workstation`, and `scvmm` all contain an identical domain join block. Should be extracted into `common_windows`.
- **Domain join has no retry/wait** — if AD replication is slow after DC01 promotion, joins on other VMs fail immediately with no backoff.
- **SCVMM `ProductKey` is blank** in the unattend INI — requires a volume license key or evaluation mode must be explicitly set.
- **Win11 license rearm is temporary** — `slmgr /rearm` buys ~90 days; workstations will nag or lock after that.
- **Domain join in `workstation` role re-uses `common_windows` IP/hostname tasks** — after a domain join reboot, Ansible reconnects as `labadmin` which is correct, but if the domain GPO later restricts local logins the role will lose connectivity.
- **WS2025 and Win11 Packer templates skip ISO checksum** (`iso_checksum = "none"`) — should be set to the SHA256 of the downloaded ISO.
- **`ws2025.pkr.hcl` shutdown command is a no-op** (`echo`) — if sysprep fails, Packer hangs until the 30-minute timeout expires.

### PowerShell / Tooling

- **Destroy-Lab.ps1** removes VMs directly; use the `terraform:destroy` CI job for provider-managed cleanup.
- **`Setup-Packer.ps1`** does not verify that the configured Packer executable exists.
- **`Build-WS2025.ps1`** adds the Packer exe directory to `$PATH` but then calls bare `packer`, not the configured path.

### Housekeeping

- Keep `terraform/terraform.tfvars.example` current when host paths or switch names change.
- Remove stale `terraform/.terraform.tfstate.lock.info` from the working tree.
- Remove `debug.PNG` from `packer/ubuntu2404/`.
- Fix stale comment in `terraform/vms.tf` (`state = Running` comment says "Create VMs stopped").
- Commit untracked utility scripts: `Build-Ubuntu.ps1`, `Build-Win11.ps1`, `Check-Prerequisites.ps1`, `Setup-Packer.ps1`.
- Remove `Build-Lab.ps1.bak` from the working tree.
- Remove `win11-build.log` and `ws2025-build.log` from the working tree (add `*.log` to `.gitignore`).
