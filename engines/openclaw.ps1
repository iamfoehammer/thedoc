# Engine: OpenClaw (not yet supported)
# Parallel stub to engines/openclaw.sh. The "not yet supported" marker in
# the comment lets setup.sh and setup.ps1's gate fall back to Claude Code
# before this script is ever exec'd.
[CmdletBinding()]
param(
    [string]$InstanceDir,
    [string]$SetupMode,
    [string]$DoctorType
)
Write-Host ''
Write-Host '  OpenClaw engine support is not yet available.'
Write-Host '  Help build it: edit this file and submit a PR!'
Write-Host ''
exit 1
