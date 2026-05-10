# thedoc bootstrap (PowerShell)
# One-liner installer for native Windows PowerShell 7+ users.
#
# Usage:
#   irm https://raw.githubusercontent.com/iamfoehammer/thedoc/main/bootstrap.ps1 | iex
#
# This is the Windows-native counterpart to bootstrap.sh. Linux/macOS/WSL/Git
# Bash users should use the bash one-liner from the README instead.

$ErrorActionPreference = 'Stop'

$Repo   = 'https://github.com/iamfoehammer/thedoc.git'
$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "thedoc-$([guid]::NewGuid())"

# ── Preflight ────────────────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "  thedoc needs git but it isn't on your PATH."
    Write-Host "  Install Git for Windows: https://git-scm.com/download/win"
    Write-Host ""
    exit 1
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host ""
    Write-Host "  thedoc PowerShell scripts target PowerShell 7+. You're on $($PSVersionTable.PSVersion)."
    Write-Host "  Install PowerShell 7: https://github.com/PowerShell/PowerShell/releases"
    Write-Host ""
    exit 1
}

# ── Clone to temp ────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Downloading thedoc..."
git clone --quiet $Repo $TmpDir
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  Failed to clone $Repo."
    Write-Host "  Check your network, or git-clone the repo manually."
    Write-Host ""
    exit 1
}
Write-Host "  Done."
Write-Host ""

# ── Hand off to setup.ps1 ─────────────────────────────────────────────
$env:THEDOC_BOOTSTRAP_DIR = $TmpDir
& (Join-Path $TmpDir 'setup.ps1')
