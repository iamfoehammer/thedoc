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
    if (-not $VarName) {
        Write-Host "Usage: secret set VAR_NAME"
        return
    }

    if ($VarName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        Write-Host "Invalid variable name: $VarName"
        Write-Host "Use letters, numbers, and underscores only."
        return
    }

    $secureValue = Read-Host -Prompt "Value for $VarName" -AsSecureString
    $value = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue))

    if ([string]::IsNullOrEmpty($value)) {
        Write-Host "No value provided. Aborted."
        return
    }

    Ensure-File

    # Remove existing entry if present
    if (Test-Path $SecretsFile) {
        $lines = Get-Content $SecretsFile | Where-Object { $_ -notmatch "^\`$env:${VarName}\s*=" }
        $lines | Set-Content $SecretsFile
    }

    # Append new entry
    Add-Content $SecretsFile "`$env:${VarName} = `"${value}`""

    # Copy variable reference to clipboard
    $varRef = "`$env:${VarName}"
    Set-Clipboard -Value $varRef

    Write-Host "Saved $VarName to $SecretsFile"
    Write-Host "Copied $varRef to clipboard."
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
    if (-not $VarName) {
        Write-Host "Usage: llm-secrets remove VAR_NAME"
        return
    }

    Ensure-File

    if (-not (Select-String -Path $SecretsFile -Pattern "^\`$env:${VarName}\s*=" -Quiet)) {
        Write-Host "$VarName not found in $SecretsFile"
        return
    }

    $lines = Get-Content $SecretsFile | Where-Object { $_ -notmatch "^\`$env:${VarName}\s*=" }
    $lines | Set-Content $SecretsFile

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
    }
}
