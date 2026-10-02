#Requires -Version 5.1
#Requires -RunAsAdministrator
# Setup-Tofu.ps1 - Prepare the local WinRM HTTPS endpoint for OpenTofu.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$listenerAddress = 'IP:127.0.0.1'
$certificateName = 'ADLabV2 OpenTofu WinRM'
$now = Get-Date

$service = Get-Service -Name WinRM
if ($service.Status -ne 'Running') {
    Start-Service -Name WinRM
}

if (-not [bool]::Parse((Get-Item WSMan:\localhost\Service\Auth\Negotiate).Value)) {
    throw 'WinRM Negotiate authentication is disabled. Enable it for the Hyper-V provider before running setup.'
}

$listeners = @(Get-WSManInstance -ResourceURI winrm/config/Listener -Enumerate)
# Reuse a working HTTPS listener, including one already managed by the host.
foreach ($listener in $listeners) {
    if ($listener.Transport -ne 'HTTPS' -or $listener.Port -ne 5986 -or
        $listener.Enabled -ne 'true' -or $listener.ListeningOn -notcontains '127.0.0.1') {
        continue
    }
    $certificate = Get-Item -LiteralPath "Cert:\LocalMachine\My\$($listener.CertificateThumbprint)" -ErrorAction SilentlyContinue
    if ($certificate -and $certificate.HasPrivateKey -and
        $certificate.NotBefore -le $now -and $certificate.NotAfter -gt $now.AddDays(30)) {
        Write-Host 'WinRM HTTPS is ready on 127.0.0.1:5986.' -ForegroundColor Green
        return
    }
}

$localListener = @($listeners | Where-Object {
    $_.Transport -eq 'HTTPS' -and $_.Address -eq $listenerAddress
}) | Select-Object -First 1
if ($localListener) {
    $existingCertificate = Get-Item -LiteralPath "Cert:\LocalMachine\My\$($localListener.CertificateThumbprint)" -ErrorAction SilentlyContinue
    if (-not $existingCertificate -or $existingCertificate.FriendlyName -ne $certificateName) {
        throw 'An existing loopback HTTPS listener needs repair and is not managed by this script. Check winrm enumerate winrm/config/listener before retrying.'
    }
}

$certificate = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
    $_.FriendlyName -eq $certificateName -and $_.HasPrivateKey -and
    $_.NotBefore -le $now -and $_.NotAfter -gt $now.AddDays(30)
} | Sort-Object NotAfter -Descending | Select-Object -First 1
if (-not $certificate) {
    $certificate = New-SelfSignedCertificate -Type SSLServerAuthentication `
        -Subject 'CN=localhost' -FriendlyName $certificateName `
        -TextExtension '2.5.29.17={text}DNS=localhost&IPAddress=127.0.0.1' `
        -CertStoreLocation Cert:\LocalMachine\My -NotAfter $now.AddYears(2)
}

$selectors = @{ Transport = 'HTTPS'; Address = $listenerAddress }
$values = @{
    Hostname = 'localhost'
    CertificateThumbprint = $certificate.Thumbprint
    Port = '5986'
    Enabled = 'true'
}
if ($localListener) {
    Set-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet $selectors -ValueSet $values | Out-Null
} else {
    New-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet $selectors -ValueSet $values | Out-Null
}

if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 5986 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    throw 'The HTTPS listener was configured, but port 5986 is unavailable on loopback. Check winrm enumerate winrm/config/listener.'
}
Write-Host 'WinRM HTTPS is ready on 127.0.0.1:5986.' -ForegroundColor Green
