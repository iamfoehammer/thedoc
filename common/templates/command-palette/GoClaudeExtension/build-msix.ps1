# Build, sign, pack and install the Go Claude Sessions Command Palette extension.
#
# The signing certificate is found by matching the Publisher in Package.appxmanifest against
# the code-signing certs in Cert:\CurrentUser\My, so this works on any machine that has one.
# Create one with New-SelfSignedCertificate (see the README) if you have none.
[CmdletBinding()]
param(
    # Overrides the certificate lookup.
    [string]$Thumbprint = $env:CMDPAL_SIGNING_THUMBPRINT,

    # Build only; skip packing, signing and installing.
    [switch]$NoInstall
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$sdkBin   = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64"
$makeappx = Join-Path $sdkBin 'makeappx.exe'
$signtool = Join-Path $sdkBin 'signtool.exe'
foreach ($tool in @($makeappx, $signtool)) {
    if (-not (Test-Path $tool)) { throw "Missing $tool - install the Windows 10 SDK (10.0.26100)" }
}

[xml]$manifest = Get-Content .\Package.appxmanifest
$publisher = $manifest.Package.Identity.Publisher
$appName   = $manifest.Package.Identity.Name

if (-not $Thumbprint) {
    $cert = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq $publisher -and $_.NotAfter -gt (Get-Date) } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
    if (-not $cert) {
        throw @"
No valid certificate for '$publisher' in Cert:\CurrentUser\My. Create one:

  `$cert = New-SelfSignedCertificate -Type Custom -Subject "$publisher" -KeyUsage DigitalSignature ``
    -FriendlyName "$appName dev" -CertStoreLocation "Cert:\CurrentUser\My" ``
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
  Import-Certificate -FilePath (Export-Certificate -Cert `$cert -FilePath dev.cer) ``
    -CertStoreLocation Cert:\LocalMachine\TrustedPeople   # needs an elevated shell

Or point at an existing one with -Thumbprint / `$env:CMDPAL_SIGNING_THUMBPRINT.
"@
    }
    $Thumbprint = $cert.Thumbprint
    Write-Host "Signing as $publisher ($Thumbprint)"
}

Write-Host "Building..."
dotnet publish -p:Platform=x64 -c Debug -o ./publish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }
if ($NoInstall) { Write-Host "Built. Skipping pack/sign/install."; return }

Write-Host "Preparing layout..."
if (Test-Path AppxLayout) { Remove-Item AppxLayout -Recurse -Force }
New-Item -ItemType Directory -Path AppxLayout\Assets -Force | Out-Null
Copy-Item publish\* AppxLayout\ -Force -Recurse
Copy-Item Package.appxmanifest AppxLayout\AppxManifest.xml -Force
Copy-Item Assets\*.png AppxLayout\Assets\ -Force

Write-Host "Packing MSIX..."
$msix = "$appName.msix"
Remove-Item $msix -ErrorAction SilentlyContinue
& $makeappx pack /d AppxLayout /p $msix /o
if ($LASTEXITCODE -ne 0) { throw "makeappx failed" }

Write-Host "Signing MSIX..."
& $signtool sign /fd SHA256 /sha1 $Thumbprint /t http://timestamp.digicert.com $msix
if ($LASTEXITCODE -ne 0) { throw "signtool failed" }

Write-Host "Installing..."
Get-AppxPackage "*$appName*" | Remove-AppxPackage -ErrorAction SilentlyContinue
Add-AppxPackage ".\$msix"

Write-Host "Done. Reload Command Palette: Start-Process x-cmdpal://reload"
