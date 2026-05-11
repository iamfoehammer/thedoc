@echo off
REM thedoc.cmd - cmd.exe / PowerShell resolver shim for thedoc.ps1.
REM
REM Windows' default PATHEXT doesn't include .PS1, so typing `thedoc`
REM from cmd won't auto-resolve to thedoc.ps1 even when the framework
REM is on PATH. This shim sits next to thedoc.ps1 and bridges the gap
REM so `thedoc <args>` works from any shell on Windows.
REM
REM Prefers PowerShell 7 (pwsh.exe); falls back to Windows PowerShell
REM 5.1 (powershell.exe) so `thedoc help` at least prints something on
REM machines without pwsh installed. setup.ps1 itself enforces PS7+.

where /q pwsh.exe
if %ERRORLEVEL% EQU 0 goto :usePwsh
goto :usePowershell

:usePwsh
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0thedoc.ps1" %*
exit /b %ERRORLEVEL%

:usePowershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0thedoc.ps1" %*
exit /b %ERRORLEVEL%
