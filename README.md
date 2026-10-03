# ADLabV2

Active Directory lab built with **Packer + OpenTofu + Ansible**.

| Tool      | Purpose                                                                  |
| --------- | ------------------------------------------------------------------------ |
| Packer    | Build reusable base VM images (WS2025, Win11, Ubuntu 24.04)              |
| OpenTofu  | Create / destroy Hyper-V VMs from those base images                      |
| Ansible   | Configure VMs (AD, CA, SQL, IIS, GitLab, SCVMM)                          |
| GitLab CE | CI/CD — running on GIT01 (Ubuntu 24.04, 192.168.100.5)                  |
| Docker CE | Ansible control-node container — runs on GIT01, not host Docker Desktop |

## VM Inventory

| Host  | IP             | OS           | Role                                             | Local admin user  |
| ----- | -------------- | ------------ | ------------------------------------------------ | ----------------- |
| GIT01 | 192.168.100.5  | Ubuntu 24.04 | GitLab CE + Ansible control node                 | `labadmin`      |
| DC01  | 192.168.100.10 | WS2025       | Primary DC, DNS, forest root                     | `Administrator` |
| DC02  | 192.168.100.11 | WS2025       | Secondary DC                                     | `Administrator` |
| CA01  | 192.168.100.20 | WS2025       | Enterprise Root CA                               | `Administrator` |
| DB01  | 192.168.100.30 | WS2025       | SQL Server Developer Edition (32 GB RAM, 8 vCPU) | `Administrator` |
| WEB01 | 192.168.100.40 | WS2025       | IIS                                              | `Administrator` |
| WKS01 | 192.168.100.50 | Win11        | Workstation                                      | `labadmin`      |
| WKS02 | 192.168.100.51 | Win11        | Workstation                                      | `labadmin`      |
| VMM01 | 192.168.100.60 | WS2025       | SCVMM 2025 (nested virt enabled)                 | `Administrator` |

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

| Tool                     | Minimum version                    | Notes                                                                                                                                                                                                                           |
| ------------------------ | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Packer                   | 1.9.0                              | `packer.exe` in `PATH` or set `PackerExe` in `config/lab.config.psd1`                                                                                                                                                   |
| OpenTofu                 | latest stable                      | `tofu.exe` in `PATH` or set `TofuExe` in `config/lab.config.psd1`                                                                                                                                                       |
| Docker Desktop           | latest                             | Bootstrap only — GIT01 takes over after first run                                                                                                                                                                              |
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

This creates the Packer switch, assigns the host adapter `10.0.0.1/24` used by
the builders, checks the installer ISOs, and installs the ADK Deployment Tools
component when `oscdimg.exe` is missing. The image build wrappers and Hyper-V CI
jobs verify the switch address and add the installed `oscdimg` directory to their
process `PATH`; they stop with setup instructions if either prerequisite is
missing. No machine-wide `PATH` change is made.

Packer's temporary Hyper-V VMs and VHDXs use the process `TEMP` directory. Set
it to a volume with sufficient free space before starting image builds:

```powershell
New-Item -ItemType Directory -Force E:\PackerTemp | Out-Null
$env:TEMP = 'E:\PackerTemp'
$env:TMP  = 'E:\PackerTemp'

# Ubuntu 24.04 (GIT01) — build first
.\Build-Ubuntu.ps1

# Windows Server 2025 (all Windows servers)
.\Build-WS2025.ps1

# Windows 11 (workstations)
.\Build-Win11.ps1
```

If Hyper-V pauses the VM with `Disk(s) encountered critical IO errors`, check
the host volume that contains the attached VHDX and its free space. A full
volume can trigger this error. For example, Packer may place the temporary
VHDX under `C:\Users\<user>\AppData\Local\Temp`; redirect `TEMP` and `TMP` to
a volume with sufficient free space before starting the build. Changing these
variables does not relocate a disk used by a build already in progress.

Convenience wrapper scripts are also available at the repo root:
`Build-Ubuntu.ps1`, `Build-WS2025.ps1`, `Build-Win11.ps1`

---

### 3. Bootstrap: Manual First Run

Run `Setup-Tofu.ps1` once from an elevated Windows PowerShell on the Hyper-V
host before creating VMs. It creates a WinRM HTTPS listener bound to
`127.0.0.1:5986`, or reuses an existing valid HTTPS listener on that endpoint.
The Hyper-V provider uses NTLM over HTTPS; its Go WinRM client requires HTTPS
when WinRM's `AllowUnencrypted` setting is false. The setup uses a self-signed
certificate, which the loopback provider accepts with `insecure = true`.
`Build-Lab.ps1` checks the port and runs `tofu init` before `tofu apply`.

```powershell
# Configure WinRM HTTPS for the local Hyper-V provider
.\Setup-Tofu.ps1

# Phase 1 - Create all VMs and bootstrap Windows networking via PowerShell Direct
# GIT01 gets its network automatically from a cloud-init seed ISO.
.\Build-Lab.ps1 -SkipAnsible
```

#### Automatic GIT01 network setup

For a **new GIT01 disk created from the updated Ubuntu base image**, OpenTofu
calls `New-Git01Seed.ps1` and attaches a cloud-init NoCloud ISO before first boot.
Ubuntu reads GIT01's IP (`192.168.100.5`), prefix, gateway, and DNS from
`config/lab.config.psd1`; the ISO contains no passwords. It uses `oscdimg.exe`
from the Windows ADK installed by `Setup-Packer.ps1`. Cloud-init applies the
address automatically, and Ansible takes over the persistent Netplan settings.
Allow the first boot to finish, then check SSH before Phase 2 below.

**Upgrading from an older Ubuntu base:** rebuild it with `.\Build-Ubuntu.ps1`
using the updated image preparation script. Existing GIT01 disks keep their
current configuration; attaching the ISO alone does not reset them. Use the
manual fallback below for an existing disk, or recreate GIT01 with a fresh copy
of the rebuilt base if its data is disposable. Recreating its disk erases its
GitLab data. Network changes should also match the Ansible inventory and group
variables. GitLab installation needs working DNS and internet access via LabNAT.

#### Manual fallback for older Ubuntu images

PowerShell Direct only bootstraps Windows guests. An older GIT01 disk can retain
Packer's `10.0.0.2/24` address. If SSH is not reachable at `192.168.100.5`, open
the console and configure it manually:

```powershell
vmconnect.exe localhost GIT01
```

Log into GIT01's console as `labadmin`, using the password supplied to Packer
through `AD_LAB_ADMIN_PASSWORD`. Run `ip -br link` to identify the Ethernet
interface. The example below uses `eth0`, as does
`ansible/roles/common_linux/templates/99-lab-static.yaml.j2`; update both if your
interface has a different name. Adjust the addresses if you changed the lab
network. The DNS values match that template, including its public DNS fallback;
GitLab installation requires working DNS and internet access through LabNAT.

The basic Ubuntu VMConnect console does not support clipboard paste. To avoid
typing the full Netplan configuration there, type only these commands in the
console (replace `eth0` if needed):

```bash
ip -br link
sudo ip addr add 192.168.100.5/24 dev eth0
```

This temporary address lets the Hyper-V host reach GIT01 over SSH. It disappears
after reboot. From PowerShell on the host, connect using the same `labadmin`
password:

```powershell
ssh labadmin@192.168.100.5
```

Paste the following commands into the SSH session to make the network settings
persistent. If `netplan apply` disconnects SSH, reconnect using the command above.

```bash

# Back up existing Netplan files before removing Packer's network configuration.
backup_dir="/etc/netplan-backup-$(date +%Y%m%d-%H%M%S)"
sudo cp -a /etc/netplan "$backup_dir"
sudo rm -f /etc/netplan/*.yaml /etc/netplan/*.yml

# Keep cloud-init from restoring the image's network configuration on reboot.
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg >/dev/null

# Use the same file that Ansible will manage after SSH becomes reachable.
sudo tee /etc/netplan/99-lab-static.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.100.5/24
      routes:
        - to: default
          via: 192.168.100.1
      nameservers:
        addresses:
          - 192.168.100.10
          - 192.168.100.11
          - 8.8.8.8
EOF
sudo chmod 600 /etc/netplan/99-lab-static.yaml
sudo netplan generate
sudo netplan apply
ip -br address
ip route
```

#### Continue with GitLab configuration

On the Hyper-V host, verify SSH is reachable before starting Phase 2. Continue
when `TcpTestSucceeded` is `True` (for either automatic setup or the fallback):

```powershell
Test-NetConnection -ComputerName 192.168.100.5 -Port 22

# Phase 2 - Bootstrap GIT01: installs Docker CE, GitLab CE, GitLab Runner,
#            and distributes GIT01's SSH public key to all other lab VMs.
#            Uses Docker Desktop on the host - last time it's needed.
.\Build-Lab.ps1 -SkipTofu -GitLabOnly

# Phase 3 - Configure domain infrastructure from the host as a one-off,
#            or skip this and let GitLab CI handle it after Phase 5.
.\Build-Lab.ps1 -SkipTofu
```

> **Note:** `site.yml` configures domain infrastructure only (DC01 through VMM01).
> GIT01 is managed exclusively via `gitlab.yml` (used by the `-GitLabOnly` flag).

---

### 4. GitLab CI Setup (one-time, after Phase 2)

Two runners are required:

| Runner tag      | Executor           | Host         | Used for                                    |
| --------------- | ------------------ | ------------ | ------------------------------------------- |
| `hyperv-host` | Shell (PowerShell) | Hyper-V host | Packer image builds, OpenTofu apply/destroy |
| `git01`       | Docker             | GIT01        | All Ansible playbooks                       |

#### A. Create the project and push your current branch (Windows host)

1. Browse to `http://192.168.100.5` and log in as `root`, using the password
   supplied through `AD_LAB_ADMIN_PASSWORD` during bootstrap.
2. Create a **blank project**, name `ADLabV2`, namespace `root`, path `adlabv2`.
   Leave **Initialize repository with a README** unchecked.
3. Create a personal access token with `write_repository` scope for Git over
   HTTP. Enter `root` as the Git username and the token at password prompts;
   do not embed the token in URLs or committed files.
4. In PowerShell, from your existing `D:\Git\ADLabV2` checkout:

```powershell
git status
git branch --show-current
git remote -v
# Add once. If gitlab already exists, inspect its URL before changing it.
git remote add gitlab http://192.168.100.5/root/adlabv2.git
git push gitlab HEAD:main
```

`HEAD:main` pushes your **current committed branch** to GitLab's `main` branch.
No local `main` or `feature/toolchain-redesign` branch is required. It preserves
the existing `origin` remote and upstream. Commit any intended local changes
before pushing; uncommitted files are not included. For later updates, use the
same explicit `git push gitlab HEAD:main` command. In GitLab, confirm `main` is
the project's default branch and protect it so protected CI variables are
available. The first pipeline can remain pending until runners are configured.

#### B. Clone and build the image (GIT01)

From the Windows host, connect with `ssh labadmin@192.168.100.5`. Run these
commands **inside that SSH session**, using `root` and your access token when
Git prompts for credentials:

```bash
git clone http://192.168.100.5/root/adlabv2.git ~/ADLabV2
cd ~/ADLabV2
sudo docker build -t adlabv2-ansible:latest docker
```

Pushing to GitLab stores the repository in GitLab; it does not create
`/home/labadmin/ADLabV2`. The clone above creates that working directory.
If it already exists, use `git -C ~/ADLabV2 pull --ff-only` instead of cloning.
The direct Docker build avoids the Compose file's Windows host volume paths.
Rebuild the image after changing `docker/Dockerfile` or its build inputs.

#### C. Create and register the GIT01 Docker runner

In the project's **Settings > CI/CD > Runners**, create a project runner for
Linux, set tag `git01`, and leave **Run untagged jobs** disabled. Copy its runner
authentication token (normally starts with `glrt-`). In GIT01's SSH session:

```bash
sudo gitlab-runner register --url http://192.168.100.5 \
  --executor docker --docker-image alpine:latest --docker-network-mode host
```

Paste the authentication token when prompted. Tags are set in the UI; this
uses the current [runner registration workflow](https://docs.gitlab.com/runner/register/).
Edit `sudo nano /etc/gitlab-runner/config.toml`. Inside this runner's existing
`[runners.docker]` section, set these entries, retaining its other settings:

```toml
network_mode = "host"
pull_policy = "if-not-present"
```

Host networking gives jobs access to LabNAT. The
[image pull policy](https://docs.gitlab.com/runner/executors/docker/#set-the-if-not-present-pull-policy)
lets the runner use the locally built `adlabv2-ansible:latest` image instead of
trying to download it from Docker Hub. Restart and check the service:

```bash
sudo systemctl restart gitlab-runner
sudo gitlab-runner verify
```

Confirm the runner appears online in GitLab.

#### D. Register the Hyper-V host Shell runner (Windows)

Install [GitLab Runner on Windows](https://docs.gitlab.com/runner/install/windows/)
as a service if it is not installed already. Its service account needs Hyper-V
access, access to configured local paths, and the Packer/OpenTofu prerequisites.
In the same project's runner UI, create another runner for Windows with tag
`hyperv-host`. Use its **separate** authentication token when prompted by this
command in elevated Windows PowerShell:

```powershell
gitlab-runner register --url http://192.168.100.5 --executor shell --shell powershell
gitlab-runner restart
gitlab-runner verify
```

Confirm this runner is also online. Packer/OpenTofu jobs require it; the default
branch pipeline includes an automatic `terraform:plan` before Ansible jobs.
Also confirm `lab_hvhost_ip` in `ansible/group_vars/all.yml` is the real host
management address and its WinRM endpoint is reachable from GIT01. The loopback
HTTPS listener created by `Setup-Tofu.ps1` serves OpenTofu only.

#### E. Add project CI variables

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

| Variable                  | Type              | Value                                                  |
| ------------------------- | ----------------- | ------------------------------------------------------ |
| `AD_LAB_ADMIN_PASSWORD` | Masked, protected | Shared Hyper-V host and lab account password           |
| `SSH_PRIVATE_KEY`       | File, visible, protected | Contents of `/home/labadmin/.ssh/id_ed25519` on GIT01 |

For `SSH_PRIVATE_KEY`, select variable type **File**, visibility **Visible**,
and **Protect variable**. Paste the complete private key, including its header
and footer, and press Enter after the final line so it ends with a newline.
Multiline SSH keys cannot be masked; see
[GitLab's SSH variable instructions](https://docs.gitlab.com/ci/jobs/ssh_keys/#add-an-ssh-key-as-a-file-type-variable).
Disable variable reference expansion. Keep the key out of CI logs and repository
files. Protected variables are supplied only to pipelines on protected refs.

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

| Collection                     | Purpose                                                               |
| ------------------------------ | --------------------------------------------------------------------- |
| `ansible.windows` ≥ 2.3.0   | Core Windows modules (`win_powershell`, `win_feature`, etc.)      |
| `community.windows` ≥ 2.2.0 | Supplemental Windows modules (`win_firewall_rule`, etc.)            |
| `ansible.posix` ≥ 1.5.0     | Linux/POSIX modules (GIT01)                                           |
| `microsoft.ad` ≥ 1.3.0      | Active Directory modules (`microsoft.ad.user`, `microsoft.ad.ou`) |

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
