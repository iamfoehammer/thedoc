# llm-secrets.ps1 - Store and manage environment variable secrets
#
# Usage:
#   llm-secrets set MY_VAR_NAME          Set a secret (prompts for value, hidden input)
#   llm-secrets list                     List secret names (not values)
#   llm-secrets remove MY_VAR_NAME       Remove a secret
#   llm-secrets help                     Show this help
#
# Secrets are stored in ~/.secrets.ps1 and dot-sourced by your PowerShell profile.
# Values never appear in terminal output or command history.
#
# Add to your PowerShell profile ($PROFILE):
#   if (Test-Path "$HOME/.secrets.ps1") { . "$HOME/.secrets.ps1" }
#   function llm-secrets { & "$HOME\GitHub\thedoc\llm-secrets.ps1" @args }

param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [string]$VarName
)

$SecretsFile = if ($env:SECRETS_FILE) { $env:SECRETS_FILE } else { Join-Path $HOME ".secrets.ps1" }

function Ensure-File {
    if (-not (Test-Path $SecretsFile)) {
        New-Item -Path $SecretsFile -ItemType File -Force | Out-Null
        if ($IsLinux -or $IsMacOS) {
            chmod 600 $SecretsFile
        } else {
            $acl = Get-Acl $SecretsFile
            $acl.SetAccessRuleProtection($true, $false)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                "FullControl", "Allow")
            $acl.SetAccessRule($rule)
            Set-Acl $SecretsFile $acl
        }
    }
}

function Set-Secret {
    # Error paths use `exit 1` (not `return`) to match the bash port's
    # exit-code contract: bad-input branches surface as non-zero so
    # wrappers / CI / scripted callers can distinguish "secret saved"
    # from "user error." Pre-iter-255 PS port always exited 0.
    if (-not $VarName) {
        Write-Host "Usage: secret set VAR_NAME"
        exit 1
    }

    if ($VarName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        Write-Host "Invalid variable name: $VarName"
        Write-Host "Use letters, numbers, and underscores only."
        exit 1
    }

    # Read the value: prefer Read-Host -AsSecureString for interactive
    # use (chars don't echo to the console), but fall back to
    # [Console]::In.ReadLine() when stdin is redirected. Read-Host
    # ignores piped stdin and blocks waiting for console input, so
    # scripted use (`echo "value" | llm-secrets.ps1 set MYVAR`) used
    # to hang. Bash `read -rsp` accepts pipe transparently; this is
    # parity with that.
    if ([Console]::IsInputRedirected) {
        $value = [Console]::In.ReadLine()
        if ($null -eq $value) { $value = '' }
    } else {
        $secureValue = Read-Host -Prompt "Value for $VarName" -AsSecureString
        $value = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue))
    }

    if ([string]::IsNullOrEmpty($value)) {
        Write-Host "No value provided. Aborted."
        exit 1
    }

    Ensure-File

    # Atomic write-then-rename so a kill mid-update can't leave the
    # secrets file in a "old entry removed, new entry not yet written"
    # state. Mirrors iter-277 cmd_set fix on the bash side, and the
    # iter-276 atomic save_state pattern. Build complete new content
    # in a tmp file, then Move-Item -Force to overwrite atomically.
    $existing = if (Test-Path -LiteralPath $SecretsFile) {
        Get-Content -LiteralPath $SecretsFile
    } else { @() }
    $wasPresent = $existing | Where-Object { $_ -match "^\`$env:${VarName}\s*=" } | Select-Object -First 1
    $newLines   = $existing | Where-Object { $_ -notmatch "^\`$env:${VarName}\s*=" }
    $newLines  += "`$env:${VarName} = `"${value}`""
    $tmp = "$SecretsFile.tmp.$PID"
    $newLines | Set-Content -LiteralPath $tmp
    Move-Item -LiteralPath $tmp -Destination $SecretsFile -Force
    if ($wasPresent) {
        Write-Host "(Updated existing secret)"
    }

    # Copy variable reference to clipboard. Set-Clipboard is Windows-only
    # in PS <7.4 and may throw on Linux pwsh (Wayland/headless sessions).
    # Catch + fall back to the platform's clipboard tool so the user still
    # gets the secret saved even when clipboard isn't available.
    $varRef = "`$env:${VarName}"
    $clipboardOk = $false
    try {
        Set-Clipboard -Value $varRef -ErrorAction Stop
        $clipboardOk = $true
    } catch {
        foreach ($tool in @(
            @{Cmd='clip.exe';  Args=@()},
            @{Cmd='pbcopy';    Args=@()},
            @{Cmd='wl-copy';   Args=@()},
            @{Cmd='xclip';     Args=@('-selection', 'clipboard')},
            @{Cmd='xsel';      Args=@('--clipboard', '--input')}
        )) {
            if (Get-Command $tool.Cmd -ErrorAction SilentlyContinue) {
                try {
                    $varRef | & $tool.Cmd @($tool.Args)
                    $clipboardOk = $true
                    break
                } catch { continue }
            }
        }
    }

    Write-Host "Saved $VarName to $SecretsFile"
    if ($clipboardOk) {
        Write-Host "Copied $varRef to clipboard."
    } else {
        Write-Host "($varRef saved but clipboard not available; copy manually if needed.)"
    }
    Write-Host "Run '. ~/.secrets.ps1' or open a new shell to load it."
}

function Get-SecretList {
    Ensure-File
    if (-not (Test-Path $SecretsFile) -or (Get-Item $SecretsFile).Length -eq 0) {
        Write-Host "No secrets stored."
        return
    }

    Write-Host "Stored secrets ($SecretsFile):"
    Get-Content $SecretsFile | ForEach-Object {
        if ($_ -match '^\$env:([A-Za-z_][A-Za-z0-9_]*)\s*=') {
            Write-Host "  $($Matches[1])"
        }
    }
}

function Remove-Secret {
    # Error paths exit 1 to match bash's cmd_remove behavior.
    if (-not $VarName) {
        Write-Host "Usage: llm-secrets remove VAR_NAME"
        exit 1
    }

    Ensure-File

    if (-not (Select-String -Path $SecretsFile -Pattern "^\`$env:${VarName}\s*=" -Quiet)) {
        Write-Host "$VarName not found in $SecretsFile"
        exit 1
    }

    # Atomic write-then-rename: build new content in tmp file, then
    # Move-Item -Force. Same pattern as iter-277 Set-Secret and
    # iter-276 Save-State. The 0-byte case (removing the last secret)
    # is handled below by writing an empty array to Set-Content
    # (which produces a 0-byte file in PS 7+, unlike piping $null
    # which is version-dependent).
    $lines = Get-Content $SecretsFile | Where-Object { $_ -notmatch "^\`$env:${VarName}\s*=" }
    $tmp = "$SecretsFile.tmp.$PID"
    if (-not $lines) {
        # Empty array -> 0-byte file. Explicit New-Item is more
        # reliable than `@() | Set-Content` across PS versions.
        Set-Content -LiteralPath $tmp -Value ''
        Clear-Content -LiteralPath $tmp
    } else {
        $lines | Set-Content -LiteralPath $tmp
    }
    Move-Item -LiteralPath $tmp -Destination $SecretsFile -Force

    Write-Host "Removed $VarName"
    Write-Host "Run '. ~/.secrets.ps1' or open a new shell to unload it."
}

function Show-Help {
    Write-Host ""
    Write-Host "  llm-secrets - Store environment variable secrets securely"
    Write-Host ""
    Write-Host "  Commands:"
    Write-Host "    llm-secrets set VAR_NAME      Set a secret (hidden input)"
    Write-Host "    llm-secrets list              List secret names (not values)"
    Write-Host "    llm-secrets remove VAR_NAME   Remove a secret"
    Write-Host "    llm-secrets help              Show this help"
    Write-Host ""
    Write-Host "  Scripted use (CI / automation):"
    Write-Host "    `"`$env:TOKEN`" | llm-secrets.ps1 set MY_TOKEN"
    Write-Host ""
    Write-Host "  Secrets are stored in ~/.secrets.ps1 (restricted permissions)."
    Write-Host "  Dot-source it in your PowerShell profile to load on startup."
    Write-Host ""
}

switch -Regex ($Command) {
    '^set$'                 { Set-Secret }
    '^list$'                { Get-SecretList }
    '^remove$'              { Remove-Secret }
    '^(help|--help|-h)$'    { Show-Help }
    default {
        Write-Host "Unknown command: $Command"
        Write-Host "Run 'llm-secrets help' for usage."
        # Bash port's switch fall-through actually invokes cmd_set with
        # the args (treating unknown commands as shorthand "set" names).
        # PS port's $Command is a single positional, so we can't
        # forward args the same way - just exit non-zero on unknown
        # input so wrappers/CI catch typos.
        exit 1
    }
}
