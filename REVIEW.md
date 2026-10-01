# ADLabV2 Project Review

**Reviewer:** Claude Code
**Date:** 2026-04-06
**Scope:** Full project - Packer, OpenTofu, Ansible, PowerShell, Docker, CI/CD

---

## 1. Project Structure Overview

Well-organized lab automation project with clear separation of concerns:
- **Packer** (3 templates: WS2025, Win11, Ubuntu 24.04) builds base VHDXs on an isolated PackerSwitch
- **OpenTofu** creates differencing-disk VMs on Hyper-V via the taliesins/hyperv provider
- **Ansible** (Docker-based control node, SSH transport) handles all post-boot configuration
- **GitLab CI** on GIT01 provides pipeline automation after initial bootstrap
- **PowerShell scripts** orchestrate the host-side bootstrap workflow

The layering (Packer > Tofu > Ansible) is clean and each tool owns its lane.

---

## 2. Security Concerns

### CRITICAL

| # | File | Issue | Fix |
|---|------|-------|-----|
| S1 | config/lab.config.psd1 | ~~Plaintext lab credentials tracked in config.~~ **Fixed:** passwords now come from `AD_LAB_ADMIN_PASSWORD` at runtime. | Keep passwords out of tracked config and rotate the shared lab password. |
| S2 | terraform/terraform.tfvars | ~~Host password stored in local Terraform variables file.~~ **Fixed:** `host_password` is supplied through `TF_VAR_host_password`; the example contains only non-secret settings. | Keep `terraform.tfvars` ignored. |
| S3 | ansible/group_vars/all.yml | ~~Plaintext service and admin passwords tracked in Ansible variables.~~ **Fixed:** password variables read `AD_LAB_ADMIN_PASSWORD` from the process environment. | Ensure Docker and GitLab jobs pass the masked variable. |
| S4 | packer/*/pkr.hcl | ~~Default Packer password tracked in templates.~~ **Fixed:** `ssh_pass` is required and supplied through `PKR_VAR_ssh_pass`. | Keep Packer password defaults absent. |
| S5 | packer/*/http/autounattend.xml | ~~Administrator password embedded in tracked answer files.~~ **Fixed:** answer files are rendered from password templates at build time. | Do not commit rendered answer media. |
| S6 | packer/ubuntu2404/http/user-data | ~~Plaintext password reset in cloud-init late commands.~~ **Fixed:** the cloud-init template receives a runtime bcrypt hash; no plaintext reset command remains. | Keep the installer template free of credentials. |

### HIGH

| # | File | Issue | Fix |
|---|------|-------|-----|
| S7 | packer/ws2025/scripts/01-init.ps1 | Enables WinRM unencrypted + Basic auth. Persists into the base image. | Add cleanup in 03-sysprep.ps1 to reset WinRM to defaults before generalize. |
| S8 | ansible/group_vars/*.yml | StrictHostKeyChecking=no globally. Comment says re-enable after initial run but no automation to do so. | Add a post-bootstrap task that populates known_hosts and removes the override. |

---

## 3. Code Quality Issues

### PowerShell Scripts

| # | File | Issue | Severity |
|---|------|-------|----------|
| Q1 | Build-WS2025.ps1 | Adds PackerExe dir to PATH but then calls bare packer, not the configured path. | Medium |
| Q2 | Destroy-Lab.ps1 | tofu destroy does not pass -var=host_password, so it will prompt or fail if terraform.tfvars is missing. | Medium |
| Q3 | Setup-Packer.ps1 | Does not verify that the configured Packer executable exists. | Low |
| Q4 | Check-Prerequisites.ps1 | ~~Used head -1 (Unix command), breaking native PowerShell.~~ **Fixed:** uses PowerShell-native output selection and checks Docker engine availability separately from CLI installation. | Medium |

### Packer Templates

| # | File | Issue | Severity |
|---|------|-------|----------|
| Q5 | ws2025.pkr.hcl | iso_checksum = none - skips ISO integrity verification. Ubuntu template has a proper SHA256. | Medium |
| Q6 | ws2025.pkr.hcl | shutdown_command is a no-op echo. If the sysprep task fails, Packer hangs 30 min before timeout. | Low |

### Terraform/OpenTofu

| # | File | Issue | Severity |
|---|------|-------|----------|
| Q7 | vms.tf | state = Running but comment says Create VMs stopped. Comment is stale. | Low |
| Q8 | Working tree | .terraform.tfstate.lock.info present - suggests a crashed or still-running tofu process. | Low |

### Ansible

| # | File | Issue | Severity |
|---|------|-------|----------|
| Q9 | 5 roles | **Domain join logic duplicated** identically in certificate_authority, sql_server, iis, workstation, and scvmm roles. Each now joins to the correct OU under `OU=NETS` (Servers or Workstations), but the duplication itself remains. | Medium |
| Q10 | sql_server/tasks/main.yml | SQL install includes SSMS in /FEATURES but SSMS is no longer bundled with SQL Server 2022. Will silently fail or error. | High |
| Q11 | scvmm/tasks/main.yml | Writes VMM service account password to an INI file on disk with no cleanup task. | Medium |
| Q12 | domain_controller/tasks/main.yml | ~~svc_vmm user created in DC role but logically belongs in SCVMM role.~~ **Fixed:** svc_vmm split into a separate "Create service accounts" task placed in `OU=Service,OU=Users,OU=NETS`. | Low |

---

## 4. Reliability and Idempotency

| # | Issue | Severity |
|---|-------|----------|
| R1 | ~~No wait_for_connection tasks after win_reboot.~~ **Fixed:** All plays now use a `block/rescue` pre_task with `wait_for_connection` (300s timeout). Unreachable hosts are skipped via `meta: end_host` without failing the run. | Medium |
| R2 | SQL ISO copy task guarded by when: sql_iso_local_path is defined but that variable is never defined. The mount task will then fail. | High |
| R3 | SCVMM ADK path defaults to D:LabSourcesADK which must be pre-staged manually. No documentation. | Medium |
| R4 | Domain join has no retry/wait logic after reboot. If AD replication is slow, subsequent tasks may fail. | Medium |

---

## 5. Recommended Improvements (Prioritized)

### High Priority
1. **Vault all credentials** - Encrypt ansible/group_vars/all.yml secrets with ansible-vault. Move lab.config.psd1 credentials to a separate gitignored file.
2. **Extract domain join** into common_windows role with a domain_member tag, eliminating duplication across 5 roles.
3. **Fix SQL SSMS feature flag** - Remove SSMS from /FEATURES; install SSMS separately if needed.
4. ~~**Add wait_for_connection** tasks after every win_reboot.~~ **Done** — block/rescue pattern in all plays.
5. **Add ISO checksum** for WS2025 Packer template.

### Medium Priority
6. **Clean up WinRM settings** in 03-sysprep.ps1 before generalize.
7. **Fix Destroy-Lab.ps1** to pass host_password variable to tofu destroy.
8. **Fix Setup-Packer.ps1** label and add actual Packer binary check.
9. **Remove cleartext chpasswd** from Ubuntu user-data late-commands.
10. **Clean up SCVMM unattend INI** after successful install.
11. **Document SQL ISO and ADK staging** requirements in README.

### Low Priority
12. Add .auto.pkrvars.hcl pattern to gitignore for Packer secrets.
13. Consolidate VHDX move post-processors into a shared script.
14. Add ansible.cfg to the project instead of relying on env vars in docker-compose.
15. Commit the untracked utility scripts (Build-Ubuntu.ps1, Build-Win11.ps1, Check-Prerequisites.ps1, Setup-Packer.ps1).
16. Remove stale terraform/.terraform.tfstate.lock.info.
17. Remove debug.PNG from packer/ubuntu2404/.

---

## 6. What is Done Well

- Clean layered architecture (Packer > Tofu > Ansible) with each tool owning its scope
- Isolated PackerSwitch for builds (no DHCP dependency, static IPs)
- Differencing disks via Tofu keep storage efficient
- SSH transport for Ansible on Windows (avoids WinRM complexity)
- GitLab CI pipeline design with separate runners for host-level and container-level jobs
- Good use of SupportsShouldProcess in Destroy-Lab.ps1
- GitLab memory tuning in gitlab.rb.j2 (appropriate for 8 GB VM)
- Sysprep via scheduled task (avoids the WinRM session drop problem)
- Comprehensive .gitignore covering secrets, state files, and large binaries
- Good comments and documentation throughout
