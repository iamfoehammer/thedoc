# Wires the Command Palette alias "go " to the Claude Sessions page, the same way "." opens
# Window Walker: type the alias, press space, and you land in the session list.
#
# The edit is a targeted text insert rather than a parse-and-reserialize, because
# settings.json contains keys that differ only by casing (ConvertFrom-Json chokes on those)
# and because a minimal diff is safer for a file the palette owns.
#
# Command Palette rewrites settings.json when it exits, so this stops the palette first and
# starts it again afterwards.
[CmdletBinding()]
param(
    [string]$Alias = 'go',

    # The page sets this Id itself (see Pages\SessionListPage.cs). Command Palette uses an
    # extension's explicit command Id verbatim.
    [string]$CommandId = 'go.claude.sessions',

    # Direct aliases fire on the alias alone. We want "<alias> <query>", so leave this off.
    [switch]$Direct,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$stateDir     = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.CommandPalette_8wekyb3d8bbwe\LocalState'
$settingsPath = Join-Path $stateDir 'settings.json'
if (-not (Test-Path $settingsPath)) { throw "Command Palette settings not found at $settingsPath" }

# Non-direct aliases are stored with a trailing space, since they expect a query after the alias.
$key = if ($Direct) { $Alias } else { "$Alias " }
$isDirect = if ($Direct) { 'true' } else { 'false' }

Write-Host "Alias '$key' -> $CommandId"

$raw = Get-Content $settingsPath -Raw
if ($raw -notmatch '"Aliases"\s*:\s*\{') { throw "No Aliases block in $settingsPath" }

# Drop any existing entry for this alias, then insert ours at the top of the block.
$entryPattern = '(?s)\s*"[^"]*"\s*:\s*\{[^{}]*?"Alias"\s*:\s*"' + [regex]::Escape($Alias) + '"[^{}]*?\},?'
$updated = [regex]::Replace($raw, $entryPattern, '')

$entry = @"
`r`n    "$key": {
      "CommandId": "$CommandId",
      "Alias": "$Alias",
      "IsDirect": $isDirect
    },
"@
$updated = [regex]::Replace($updated, '"Aliases"\s*:\s*\{', { param($m) $m.Value + $entry }, 1)

# Sanity check before touching anything: it still has to be valid JSON.
try { $null = $updated | ConvertFrom-Json -AsHashtable } catch { throw "Edit produced invalid JSON: $_" }

if ($DryRun) {
    Write-Host "(dry run, nothing written)"
    ($updated -split "`n" | Select-String -Pattern '"Aliases"' -Context 0, 6).ToString()
    return
}

$palette = Get-Process 'Microsoft.CmdPal.UI' -ErrorAction SilentlyContinue
if ($palette) {
    Write-Host "Stopping Command Palette so it does not overwrite settings..."
    $palette | Stop-Process -Force
    Start-Sleep -Milliseconds 1200
}

$backup = "$settingsPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $settingsPath $backup
Set-Content $settingsPath $updated -Encoding UTF8 -NoNewline
Write-Host "Backup: $backup"

Write-Host "Starting Command Palette..."
Start-Process 'explorer.exe' 'shell:AppsFolder\Microsoft.CommandPalette_8wekyb3d8bbwe!App'
Start-Sleep -Seconds 3

Write-Host "Done. Open the palette and type '$Alias ' to land in the session list."
