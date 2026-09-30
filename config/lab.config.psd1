@{
    # === Domain ===
    DomainName        = 'lab.local'
    DomainNetbiosName = 'LAB'
    DomainDN          = 'DC=lab,DC=local'

    # === Network ===
    SwitchName        = 'LabSwitch'
    NetworkPrefix     = '192.168.100'
    SubnetMask        = '255.255.255.0'
    PrefixLength      = 24
    GatewayIP         = '192.168.100.1'
    DnsServer1        = '192.168.100.10'   # DC01
    DnsServer2        = '192.168.100.11'   # DC02

    # === Packer Build Network (isolated) ===
    PackerSwitch      = 'PackerSwitch'
    PackerBuildIP     = '10.0.0.2'
    PackerBuildGw     = '10.0.0.1'
    PackerBuildPfx    = 24

    # === Paths ===
    LabRoot           = 'D:\CODE\ADLabV2'
    BaseVhdDir        = 'D:\CODE\ADLabV2\base-vhds'
    VMDir             = 'D:\CODE\ADLabV2\vms'
    PackerDir         = 'D:\CODE\ADLabV2\packer'
    PackerExe         = 'D:\Tools\packer\packer.exe'
    TofuExe           = 'D:\Tools\tofu\tofu.exe'     # or 'tofu' if in PATH

    # === ISOs ===
    WS2025ISO         = 'D:\LabSources\ISOs\Windows_Server_2025_EVAL_x64FRE_en-us.iso'
    Win11ISO          = 'D:\LabSources\ISOs\Windows_11_Enterprise_EVAL_x64_en-us.iso'
    Ubuntu2404ISO     = 'D:\LabSources\ISOs\ubuntu-24.04.4-live-server-amd64.iso'

    # === Base VHDs (Packer output) ===
    WS2025BaseVHD     = 'D:\CODE\ADLabV2\base-vhds\ws2025-base.vhdx'
    Win11BaseVHD      = 'D:\CODE\ADLabV2\base-vhds\win11-base.vhdx'
    Ubuntu2404BaseVHD = 'D:\CODE\ADLabV2\base-vhds\ubuntu2404-base.vhdx'

    # === Credentials (lab use only — not production) ===
    LocalAdminUser    = 'Administrator'
    LocalAdminPass    = 'P@ssw0rd!Lab1'

    DomainAdminUser   = 'LAB\Administrator'
    DomainAdminPass   = 'P@ssw0rd!Lab1'

    DSRMPass          = 'P@ssw0rd!DSRM1'
    SqlSAPass         = 'P@ssw0rd!SA1'

    VmmSvcUser        = 'svc_vmm'
    VmmSvcPass        = 'P@ssw0rd!VMM1'

    # Linux VM credentials (GIT01)
    LinuxUser         = 'labadmin'
    LinuxPass         = 'P@ssw0rd!Lab1'

    # === VM Definitions ===
    # ParentVHD: 'WS2025' | 'Win11' | 'Ubuntu2404'
    VMs               = @(
        @{
            Name      = 'GIT01'
            IP        = '192.168.100.5'
            RAM       = 8GB
            CPU       = 4
            ParentVHD = 'Ubuntu2404'
            Role      = 'GitLab'
            Domain    = $false   # Not a domain member
        }
        @{
            Name      = 'DC01'
            IP        = '192.168.100.10'
            RAM       = 8GB
            CPU       = 4
            ParentVHD = 'WS2025'
            Role      = 'PrimaryDC'
            Domain    = $true
        }
        @{
            Name      = 'DC02'
            IP        = '192.168.100.11'
            RAM       = 8GB
            CPU       = 4
            ParentVHD = 'WS2025'
            Role      = 'SecondaryDC'
            Domain    = $true
        }
        @{
            Name      = 'CA01'
            IP        = '192.168.100.20'
            RAM       = 8GB
            CPU       = 4
            ParentVHD = 'WS2025'
            Role      = 'EnterpriseCA'
            Domain    = $true
        }
        @{
            Name      = 'DB01'
            IP        = '192.168.100.30'
            RAM       = 32GB
            CPU       = 8
            ParentVHD = 'WS2025'
            Role      = 'SQLServer'
            Domain    = $true
        }
        @{
            Name      = 'WEB01'
            IP        = '192.168.100.40'
            RAM       = 8GB
            CPU       = 4
            ParentVHD = 'WS2025'
            Role      = 'IIS'
            Domain    = $true
        }
        @{
            Name      = 'WKS01'
            IP        = '192.168.100.50'
            RAM       = 8GB
            CPU       = 4
            ParentVHD = 'Win11'
            Role      = 'Workstation'
            Domain    = $true
        }
        @{
            Name      = 'WKS02'
            IP        = '192.168.100.51'
            RAM       = 8GB
            CPU       = 4
            ParentVHD = 'Win11'
            Role      = 'Workstation'
            Domain    = $true
        }
        @{
            Name      = 'VMM01'
            IP        = '192.168.100.60'
            RAM       = 16GB
            CPU       = 4
            ParentVHD = 'WS2025'
            Role      = 'SCVMM'
            Domain    = $true
        }
    )
}
