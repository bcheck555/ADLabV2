function Get-PackerIsoToolPath {
    $command = Get-Command oscdimg.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not $programFilesX86) { return $null }

    $adkToolRoots = @(
        (Join-Path $programFilesX86 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg'),
        (Join-Path $programFilesX86 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg')
    )
    foreach ($root in $adkToolRoots) {
        $candidate = Join-Path $root 'oscdimg.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    return $null
}

function Initialize-PackerIsoToolPath {
    $oscdimgPath = Get-PackerIsoToolPath
    if (-not $oscdimgPath) {
        throw 'Could not find oscdimg.exe. Run .\Setup-Packer.ps1 from elevated PowerShell after populating LabSources.'
    }

    $toolDirectory = Split-Path -Parent $oscdimgPath
    if ($toolDirectory -notin ($env:PATH -split ';')) {
        $env:PATH = "$toolDirectory;$env:PATH"
    }

    return $oscdimgPath
}

function Get-PackerHostNetworkStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SwitchName,
        [Parameter(Mandatory)][string]$IPAddress,
        [Parameter(Mandatory)][int]$PrefixLength
    )

    $adapterName = "vEthernet ($SwitchName)"
    $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
    if (-not $adapter) { return $null }

    $address = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $IPAddress -and $_.PrefixLength -eq $PrefixLength } |
        Select-Object -First 1
    if (-not $address) { return $null }

    return [pscustomobject]@{
        AdapterName    = $adapterName
        InterfaceIndex = $adapter.ifIndex
        IPAddress      = $address.IPAddress
        PrefixLength   = $address.PrefixLength
    }
}

function Set-PackerHostNetwork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SwitchName,
        [Parameter(Mandatory)][string]$IPAddress,
        [Parameter(Mandatory)][int]$PrefixLength
    )

    $adapterName = "vEthernet ($SwitchName)"
    $adapter = $null
    for ($attempt = 0; $attempt -lt 30 -and -not $adapter; $attempt++) {
        $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
        if (-not $adapter) { Start-Sleep -Seconds 1 }
    }
    if (-not $adapter) {
        throw "Hyper-V host adapter '$adapterName' was not created. Verify the internal switch exists, then rerun .\Setup-Packer.ps1."
    }

    $conflict = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $IPAddress -and $_.InterfaceIndex -ne $adapter.ifIndex } |
        Select-Object -First 1
    if ($conflict) {
        throw "Packer host IP $IPAddress is already assigned to interface index $($conflict.InterfaceIndex). Resolve the address conflict before setup."
    }

    $addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $incorrect = @($addresses | Where-Object {
        $_.IPAddress -ne $IPAddress -or $_.PrefixLength -ne $PrefixLength
    })
    foreach ($address in $incorrect) {
        Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $address.IPAddress -Confirm:$false -ErrorAction Stop
    }

    if (-not (Get-PackerHostNetworkStatus -SwitchName $SwitchName -IPAddress $IPAddress -PrefixLength $PrefixLength)) {
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -ErrorAction Stop | Out-Null
    }

    $status = Get-PackerHostNetworkStatus -SwitchName $SwitchName -IPAddress $IPAddress -PrefixLength $PrefixLength
    if (-not $status) {
        throw "Failed to assign $IPAddress/$PrefixLength to '$adapterName'."
    }
    return $status
}

function Assert-PackerHostNetwork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SwitchName,
        [Parameter(Mandatory)][string]$IPAddress,
        [Parameter(Mandatory)][int]$PrefixLength
    )

    $status = Get-PackerHostNetworkStatus -SwitchName $SwitchName -IPAddress $IPAddress -PrefixLength $PrefixLength
    if (-not $status) {
        throw "Packer host adapter 'vEthernet ($SwitchName)' must have $IPAddress/$PrefixLength. Run .\Setup-Packer.ps1 from elevated PowerShell."
    }
    return $status
}
