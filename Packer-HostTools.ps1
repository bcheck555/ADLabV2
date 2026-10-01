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
