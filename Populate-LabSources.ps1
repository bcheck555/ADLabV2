#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Downloads, stages, and validates the media required by ADLabV2.

.DESCRIPTION
Run this script on the Windows Hyper-V host. Downloads are written through
BITS to .partial files and moved into place only after validation succeeds.
Evaluation Center media can instead be supplied with the local-path
parameters when an interactive registration or licensed download is required.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Root = 'D:\LabSources',

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$ValidateOnly,

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$WindowsServerIsoPath,

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$Windows11IsoPath,

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$SqlServerIsoPath,

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [string]$ScvmmMediaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$sourceUrls = [ordered]@{
    WindowsServer = 'https://go.microsoft.com/fwlink/?linkid=2345730&clcid=0x409&culture=en-us&country=us'
    Windows11     = 'https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us'
    Ubuntu        = 'https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-live-server-amd64.iso'
    PowerShell    = 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/PowerShell-7.6.6-win-x64.msi'
    OpenSSH       = 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64-v10.0.0.0.msi'
    SqlBootstrap  = 'https://go.microsoft.com/fwlink/?linkid=2215202&clcid=0x409&culture=en-us&country=us'
    Odbc          = 'https://go.microsoft.com/fwlink/?linkid=2378279'
    SqlCmd        = 'https://go.microsoft.com/fwlink/?linkid=2370127'
    Adk           = 'https://go.microsoft.com/fwlink/?linkid=2289980'
    AdkWinPE      = 'https://go.microsoft.com/fwlink/?linkid=2289981'
    Scvmm         = 'https://go.microsoft.com/fwlink/?linkid=2292412&clcid=0x409&culture=en-us&country=us'
}

$knownHashes = @{
    Ubuntu     = 'E907D92EEEC9DF64163A7E454CBC8D7755E8DDC7ED42F99DBC80C40F1A138433'
    PowerShell = '958838FF55091E1C8705D89EFED0CC7E8245A3A6EF6C0CCFAE20015227108AD8'
    OpenSSH    = 'DDEC9C53864280759CF9F74791CEFD387100E3946AA849A1C138A4ED1B96B7D9'
}

$isoDirectory = Join-Path $Root 'ISOs'
$packageDirectory = Join-Path $Root 'SoftwarePackages'
$stagingDirectory = Join-Path $Root '.staging'
$adkDirectory = Join-Path $packageDirectory 'ADK'
$adkWinPeDirectory = Join-Path $packageDirectory 'ADKWinPE'
$scvmmDirectory = Join-Path $packageDirectory 'SCVMM2025'

$paths = [ordered]@{
    WindowsServer = Join-Path $isoDirectory 'Windows_Server_2025_EVAL_x64FRE_en-us.iso'
    Windows11     = Join-Path $isoDirectory 'Windows_11_Enterprise_EVAL_x64_en-us.iso'
    Ubuntu        = Join-Path $isoDirectory 'ubuntu-24.04.4-live-server-amd64.iso'
    SqlServer     = Join-Path $packageDirectory 'SQLServer2022-DEV-x64-ENU.iso'
    PowerShell    = Join-Path $packageDirectory 'PowerShell-7.6.6-win-x64.msi'
    OpenSSH       = Join-Path $packageDirectory 'OpenSSH-Win64-v10.0.0.0.msi'
    Odbc          = Join-Path $packageDirectory 'msodbcsql.msi'
    SqlCmd        = Join-Path $packageDirectory 'MsSqlCmdLnUtils.msi'
}

$inventory = [System.Collections.Generic.List[object]]::new()

function Write-Step {
    param([string]$Message)
    Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor Cyan
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedHash
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file not found: $Path"
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($ExpectedHash -and $actual -ne $ExpectedHash.ToUpperInvariant()) {
        throw "SHA-256 mismatch for $Path. Expected $ExpectedHash; received $actual."
    }
    return $actual
}

function Assert-MicrosoftSignature {
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Authenticode validation failed for ${Path}: $($signature.StatusMessage)"
    }
    if (-not $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(^|, )O=Microsoft Corporation(,|$)') {
        throw "Unexpected Authenticode signer for ${Path}: $($signature.SignerCertificate.Subject)"
    }
}

function Receive-BitsFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Name
    )

    Import-Module BitsTransfer -ErrorAction Stop
    $partial = "$Destination.partial"
    $displayName = "ADLabV2-$Name"
    $job = Get-BitsTransfer -ErrorAction SilentlyContinue |
        Where-Object DisplayName -eq $displayName |
        Select-Object -First 1

    if ($Force) {
        if ($job) {
            Remove-BitsTransfer -BitsJob $job -Confirm:$false
            $job = $null
        }
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    }

    if (-not $job) {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        Write-Step "Starting resumable download: $Name"
        $job = Start-BitsTransfer -Source $Uri -Destination $partial -DisplayName $displayName -Asynchronous
    }
    else {
        Write-Step "Resuming BITS download: $Name"
        if ($job.JobState -in @('Suspended', 'TransientError')) {
            Resume-BitsTransfer -BitsJob $job -Asynchronous
        }
    }

    $lastProgress = -1
    while ($true) {
        $job = Get-BitsTransfer -JobId $job.JobId
        switch ($job.JobState) {
            'Transferred' {
                Complete-BitsTransfer -BitsJob $job
                Move-Item -LiteralPath $partial -Destination $Destination -Force
                return
            }
            'TransientError' {
                Write-Warning "Transient BITS error for $Name; retrying: $($job.ErrorDescription)"
                Resume-BitsTransfer -BitsJob $job -Asynchronous
                Start-Sleep -Seconds 5
            }
            'Error' {
                throw "BITS download failed for ${Name}: $($job.ErrorDescription)"
            }
            'Cancelled' {
                throw "BITS download was cancelled for $Name."
            }
            default {
                if ($job.BytesTotal -gt 0) {
                    $percent = [int](100 * $job.BytesTransferred / $job.BytesTotal)
                    if ($percent -ge ($lastProgress + 5)) {
                        Write-Host "  ${Name}: $percent%"
                        $lastProgress = $percent
                    }
                }
                Start-Sleep -Seconds 2
            }
        }
    }
}

function Get-Artifact {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Uri,
        [string]$LocalPath,
        [string]$ExpectedHash,
        [string]$Version,
        [switch]$MicrosoftSigned
    )

    $needsMaterialization = $Force -or -not (Test-Path -LiteralPath $Destination -PathType Leaf)
    if ($needsMaterialization) {
        if ($ValidateOnly) {
            throw "Validation failed because $Name is missing: $Destination"
        }
        if ($Force) {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        }
        $partial = "$Destination.partial"
        if ($LocalPath) {
            Write-Step "Copying local media: $Name"
            Copy-Item -LiteralPath $LocalPath -Destination $partial -Force
            Move-Item -LiteralPath $partial -Destination $Destination -Force
        }
        elseif ($Uri) {
            Receive-BitsFile -Uri $Uri -Destination $Destination -Name $Name
        }
        else {
            throw "No source was supplied for $Name."
        }
    }
    else {
        Write-Step "Using existing file: $Name"
    }

    $hash = Assert-FileHash -Path $Destination -ExpectedHash $ExpectedHash
    if ($MicrosoftSigned) {
        Assert-MicrosoftSignature -Path $Destination
    }

    $item = Get-Item -LiteralPath $Destination
    $inventory.Add([pscustomobject]@{
        Name         = $Name
        Version      = $Version
        Path         = $item.FullName
        Source       = if ($LocalPath) { $LocalPath } else { $Uri }
        Bytes        = $item.Length
        SHA256       = $hash
        Verification = if ($MicrosoftSigned) { 'SHA256; Microsoft Authenticode' } elseif ($ExpectedHash) { 'Published SHA256' } else { 'SHA256; media content' }
    })
}

function Initialize-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        if ($ValidateOnly) {
            throw "Required directory is missing: $Path"
        }
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Install-OfflineLayout {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$BootstrapperUri,
        [Parameter(Mandatory)][string]$BootstrapperName,
        [Parameter(Mandatory)][string]$LayoutPath,
        [Parameter(Mandatory)][string]$ExpectedSetupName,
        [Parameter(Mandatory)][string]$Version
    )

    $expectedSetup = Join-Path $LayoutPath $ExpectedSetupName
    $hasLayout = (Test-Path -LiteralPath $expectedSetup -PathType Leaf) -and
        (@(Get-ChildItem -LiteralPath $LayoutPath -Force).Count -gt 1)

    if ($Force -or -not $hasLayout) {
        if ($ValidateOnly) {
            throw "$Name offline layout is incomplete: $LayoutPath"
        }
        if ($Force -and (Test-Path -LiteralPath $LayoutPath)) {
            Remove-Item -LiteralPath $LayoutPath -Recurse -Force
        }
        Initialize-Directory -Path $LayoutPath
        $bootstrapper = Join-Path $stagingDirectory $BootstrapperName
        Get-Artifact -Name "$Name bootstrapper" -Destination $bootstrapper -Uri $BootstrapperUri -Version $Version -MicrosoftSigned
        $quotedLayout = '"' + $LayoutPath + '"'
        Write-Step "Creating $Name offline layout"
        $process = Start-Process -FilePath $bootstrapper -ArgumentList "/layout $quotedLayout /quiet /norestart" -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "$Name layout failed with exit code $($process.ExitCode)."
        }
        if (-not (Test-Path -LiteralPath $expectedSetup -PathType Leaf)) {
            Copy-Item -LiteralPath $bootstrapper -Destination $expectedSetup -Force
        }
    }
    else {
        Write-Step "Using existing offline layout: $Name"
    }

    Assert-MicrosoftSignature -Path $expectedSetup
    $hash = Assert-FileHash -Path $expectedSetup
    $item = Get-Item -LiteralPath $expectedSetup
    $inventory.Add([pscustomobject]@{
        Name = $Name
        Version = $Version
        Path = $item.FullName
        Source = $BootstrapperUri
        Bytes = $item.Length
        SHA256 = $hash
        Verification = 'Offline layout; Microsoft Authenticode'
    })
}

function Install-SqlServerMedia {
    $destination = $paths.SqlServer
    if ($Force -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        if ($ValidateOnly) {
            throw "SQL Server media is missing: $destination"
        }
        if ($SqlServerIsoPath) {
            Get-Artifact -Name 'SQL Server 2022 Developer' -Destination $destination -LocalPath $SqlServerIsoPath -Version '2022 Developer'
            return
        }

        $bootstrapper = Join-Path $stagingDirectory 'SQL2022-SSEI-Dev.exe'
        Get-Artifact -Name 'SQL Server 2022 media downloader' -Destination $bootstrapper -Uri $sourceUrls.SqlBootstrap -Version '2022' -MicrosoftSigned
        $downloadDirectory = Join-Path $stagingDirectory 'sql2022-media'
        if (Test-Path -LiteralPath $downloadDirectory) {
            Remove-Item -LiteralPath $downloadDirectory -Recurse -Force
        }
        New-Item -Path $downloadDirectory -ItemType Directory -Force | Out-Null
        $quotedPath = '"' + $downloadDirectory + '"'
        Write-Step 'Downloading SQL Server 2022 Developer ISO'
        $process = Start-Process -FilePath $bootstrapper -ArgumentList "/Action=Download /MediaType=ISO /MediaPath=$quotedPath /Quiet" -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "SQL Server media download failed with exit code $($process.ExitCode). Supply -SqlServerIsoPath to use local media."
        }
        $downloadedIso = Get-ChildItem -LiteralPath $downloadDirectory -Filter '*.iso' -File -Recurse |
            Sort-Object Length -Descending |
            Select-Object -First 1
        if (-not $downloadedIso) {
            throw "SQL Server downloader did not produce an ISO. Supply -SqlServerIsoPath to use local media."
        }
        Move-Item -LiteralPath $downloadedIso.FullName -Destination $destination -Force
    }

    if (-not ($inventory | Where-Object Name -eq 'SQL Server 2022 Developer')) {
        Get-Artifact -Name 'SQL Server 2022 Developer' -Destination $destination -Uri $sourceUrls.SqlBootstrap -Version '2022 Developer'
    }
}

function Install-ScvmmMedia {
    $setupPath = Join-Path $scvmmDirectory 'setup.exe'
    if ($Force -or -not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        if ($ValidateOnly) {
            throw "SCVMM media is incomplete: $setupPath"
        }

        if (Test-Path -LiteralPath $scvmmDirectory) {
            Remove-Item -LiteralPath $scvmmDirectory -Recurse -Force
        }
        New-Item -Path $scvmmDirectory -ItemType Directory -Force | Out-Null

        if ($ScvmmMediaPath -and (Test-Path -LiteralPath $ScvmmMediaPath -PathType Container)) {
            Write-Step 'Copying extracted SCVMM 2025 media'
            Copy-Item -Path (Join-Path $ScvmmMediaPath '*') -Destination $scvmmDirectory -Recurse -Force
        }
        else {
            $mediaFile = if ($ScvmmMediaPath) {
                $ScvmmMediaPath
            }
            else {
                $downloaded = Join-Path $stagingDirectory 'SCVMM_2025.exe'
                Get-Artifact -Name 'SCVMM 2025 evaluation package' -Destination $downloaded -Uri $sourceUrls.Scvmm -Version '2025' -MicrosoftSigned
                $downloaded
            }

            $extractDirectory = Join-Path $stagingDirectory 'scvmm-extracted'
            if (Test-Path -LiteralPath $extractDirectory) {
                Remove-Item -LiteralPath $extractDirectory -Recurse -Force
            }
            New-Item -Path $extractDirectory -ItemType Directory -Force | Out-Null

            if ([IO.Path]::GetExtension($mediaFile) -ieq '.zip') {
                Expand-Archive -LiteralPath $mediaFile -DestinationPath $extractDirectory -Force
            }
            else {
                Assert-MicrosoftSignature -Path $mediaFile
                $quotedExtract = '"' + $extractDirectory + '"'
                Write-Step 'Extracting SCVMM 2025 media'
                $process = Start-Process -FilePath $mediaFile -ArgumentList "/Q /T:$quotedExtract" -Wait -PassThru
                if ($process.ExitCode -ne 0) {
                    throw "SCVMM extraction failed with exit code $($process.ExitCode). Supply -ScvmmMediaPath with extracted media."
                }
            }

            $extractedSetup = Get-ChildItem -LiteralPath $extractDirectory -Filter 'setup.exe' -File -Recurse |
                Where-Object FullName -notmatch '[\\/]Prerequisites[\\/]' |
                Select-Object -First 1
            if (-not $extractedSetup) {
                throw "No SCVMM setup.exe was found after extraction. Supply -ScvmmMediaPath with extracted media."
            }
            Copy-Item -Path (Join-Path $extractedSetup.Directory.FullName '*') -Destination $scvmmDirectory -Recurse -Force
        }
    }
    else {
        Write-Step 'Using existing extracted media: SCVMM 2025'
    }

    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        throw "SCVMM setup.exe must be located at $setupPath"
    }
    Assert-MicrosoftSignature -Path $setupPath
    $hash = Assert-FileHash -Path $setupPath
    $item = Get-Item -LiteralPath $setupPath
    $inventory.Add([pscustomobject]@{
        Name = 'SCVMM 2025'
        Version = '2025 evaluation'
        Path = $item.FullName
        Source = if ($ScvmmMediaPath) { $ScvmmMediaPath } else { $sourceUrls.Scvmm }
        Bytes = $item.Length
        SHA256 = $hash
        Verification = 'Extracted media; Microsoft Authenticode'
    })
}

function Test-IsoContents {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('WindowsServer', 'Windows11', 'Ubuntu', 'SqlServer')][string]$Kind
    )

    Write-Step "Mounting and validating $Kind media"
    $image = Mount-DiskImage -ImagePath $Path -Access ReadOnly -PassThru
    try {
        $volume = $image | Get-Volume | Where-Object DriveLetter | Select-Object -First 1
        if (-not $volume) {
            throw "Mounted ISO has no readable volume: $Path"
        }
        $mediaRoot = "$($volume.DriveLetter):\"
        switch ($Kind) {
            'Ubuntu' {
                if (-not (Test-Path -LiteralPath (Join-Path $mediaRoot 'casper\vmlinuz'))) {
                    throw "Ubuntu installer content was not found in $Path"
                }
            }
            'SqlServer' {
                if (-not (Test-Path -LiteralPath (Join-Path $mediaRoot 'setup.exe'))) {
                    throw "SQL Server setup.exe was not found in $Path"
                }
            }
            default {
                $installImage = @(
                    Join-Path $mediaRoot 'sources\install.wim'
                    Join-Path $mediaRoot 'sources\install.esd'
                ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
                if (-not $installImage) {
                    throw "Windows install.wim/install.esd was not found in $Path"
                }
                $names = @(Get-WindowsImage -ImagePath $installImage | Select-Object -ExpandProperty ImageName)
                $pattern = if ($Kind -eq 'WindowsServer') { 'Windows Server 2025' } else { 'Windows 11 Enterprise' }
                if (-not ($names -match $pattern)) {
                    throw "Expected edition '$pattern' was not found in $Path. Editions: $($names -join ', ')"
                }
            }
        }
    }
    finally {
        Dismount-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue
    }
}

function Write-InventoryReports {
    $ordered = $inventory | Sort-Object Name
    $hashLines = foreach ($entry in $ordered) {
        $relative = $entry.Path.Substring($Root.TrimEnd('\').Length).TrimStart('\')
        '{0} *{1}' -f $entry.SHA256.ToLowerInvariant(), $relative
    }
    $hashLines | Set-Content -LiteralPath (Join-Path $Root 'SHA256SUMS.txt') -Encoding ASCII

    $report = foreach ($entry in $ordered) {
        [pscustomobject]@{
            Name = $entry.Name
            Version = $entry.Version
            SizeGiB = [math]::Round($entry.Bytes / 1GB, 3)
            Path = $entry.Path
            SHA256 = $entry.SHA256
            Source = $entry.Source
            Verification = $entry.Verification
        }
    }
    $report | Format-List | Out-String -Width 4096 |
        Set-Content -LiteralPath (Join-Path $Root 'INVENTORY.txt') -Encoding UTF8
    $report | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $Root 'LabSources.inventory.json') -Encoding UTF8
}

Write-Step "ADLabV2 media root: $Root"
foreach ($directory in @($Root, $isoDirectory, $packageDirectory)) {
    Initialize-Directory -Path $directory
}
if (-not $ValidateOnly) {
    Initialize-Directory -Path $stagingDirectory
}

if (($Force -or -not (Test-Path -LiteralPath $paths.Windows11 -PathType Leaf)) -and -not $Windows11IsoPath) {
    throw "Microsoft requires interactive registration for the Windows 11 Enterprise evaluation ISO. Download it from $($sourceUrls.Windows11), then rerun with -Windows11IsoPath."
}
Get-Artifact -Name 'Windows Server 2025 Evaluation' -Destination $paths.WindowsServer -Uri $sourceUrls.WindowsServer -LocalPath $WindowsServerIsoPath -Version '2025 Evaluation'
Get-Artifact -Name 'Windows 11 Enterprise Evaluation' -Destination $paths.Windows11 -Uri $sourceUrls.Windows11 -LocalPath $Windows11IsoPath -Version 'Current x64 Evaluation'
Get-Artifact -Name 'Ubuntu Server' -Destination $paths.Ubuntu -Uri $sourceUrls.Ubuntu -ExpectedHash $knownHashes.Ubuntu -Version '24.04.4 LTS'
Get-Artifact -Name 'PowerShell' -Destination $paths.PowerShell -Uri $sourceUrls.PowerShell -ExpectedHash $knownHashes.PowerShell -Version '7.6.6' -MicrosoftSigned
Get-Artifact -Name 'Win32 OpenSSH' -Destination $paths.OpenSSH -Uri $sourceUrls.OpenSSH -ExpectedHash $knownHashes.OpenSSH -Version '10.0.0.0p2 Preview' -MicrosoftSigned
Get-Artifact -Name 'Microsoft ODBC Driver for SQL Server' -Destination $paths.Odbc -Uri $sourceUrls.Odbc -Version '18.7.1.1 x64' -MicrosoftSigned
Get-Artifact -Name 'SQL Server command-line utilities' -Destination $paths.SqlCmd -Uri $sourceUrls.SqlCmd -Version 'Current x64' -MicrosoftSigned

Install-SqlServerMedia
Install-OfflineLayout -Name 'Windows ADK' -BootstrapperUri $sourceUrls.Adk -BootstrapperName 'adksetup.exe' -LayoutPath $adkDirectory -ExpectedSetupName 'adksetup.exe' -Version '10.1.26100.9457'
Install-OfflineLayout -Name 'Windows ADK WinPE add-on' -BootstrapperUri $sourceUrls.AdkWinPE -BootstrapperName 'adkwinpesetup.exe' -LayoutPath $adkWinPeDirectory -ExpectedSetupName 'adkwinpesetup.exe' -Version '10.1.26100.9457'
Install-ScvmmMedia

Test-IsoContents -Path $paths.WindowsServer -Kind WindowsServer
Test-IsoContents -Path $paths.Windows11 -Kind Windows11
Test-IsoContents -Path $paths.Ubuntu -Kind Ubuntu
Test-IsoContents -Path $paths.SqlServer -Kind SqlServer

Write-InventoryReports
Write-Host ''
Write-Host 'LabSources population and validation completed successfully.' -ForegroundColor Green
Write-Host "Inventory: $(Join-Path $Root 'INVENTORY.txt')"
Write-Host "Hashes:    $(Join-Path $Root 'SHA256SUMS.txt')"
