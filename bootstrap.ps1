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
# Capture stderr so we can show it under our framing. Without this the user
# sees raw 'fatal: Could not resolve host' from git mixed into the install
# output with no context on what bootstrap was doing.
$cloneErr = & git clone --quiet $Repo $TmpDir 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  Clone failed. git said:"
    $cloneErr | ForEach-Object { Write-Host "      $_" }
    Write-Host ""
    Write-Host "  Common causes:"
    Write-Host "    - no network connectivity"
    Write-Host "    - corporate proxy or firewall blocking github.com"
    Write-Host "    - $Repo has moved or is unreachable"
    Write-Host ""
    exit 1
}
Write-Host "  Done."
Write-Host ""

# ── Hand off to setup.ps1 ─────────────────────────────────────────────
$env:THEDOC_BOOTSTRAP_DIR = $TmpDir
& (Join-Path $TmpDir 'setup.ps1')
