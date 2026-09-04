using System;
using System.Diagnostics;
using System.IO;

namespace GoClaudeExtension.Commands;

/// <summary>Opens a PowerShell 7 window in a folder and runs a claude command in it.</summary>
internal static class TerminalLauncher
{
    /// <summary>Set GO_TERMINAL=wt to open a Windows Terminal tab instead of a bare pwsh window.</summary>
    private const string TerminalOverrideVariable = "GO_TERMINAL";

    /// <param name="workingDirectory">Null, or a folder that no longer exists, starts in the user profile.</param>
    public static void Launch(string? workingDirectory, string claudeCommand)
    {
        var dir = !string.IsNullOrEmpty(workingDirectory) && Directory.Exists(workingDirectory)
            ? workingDirectory
            : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        // The command goes inside a quoted -Command argument, so its own quotes need escaping.
        claudeCommand = claudeCommand.Replace("\"", "\\\"");

        var pwsh = ResolvePwsh();
        var useWindowsTerminal = string.Equals(
            Environment.GetEnvironmentVariable(TerminalOverrideVariable),
            "wt",
            StringComparison.OrdinalIgnoreCase);

        var wt = useWindowsTerminal ? ResolveWindowsTerminal() : null;
        var psi = wt is null
            ? new ProcessStartInfo(pwsh)
            {
                Arguments = $"-NoExit -Command \"{claudeCommand}\"",
                WorkingDirectory = dir,
                UseShellExecute = true,
            }
            : new ProcessStartInfo(wt)
            {
                Arguments = $"-w 0 nt -d \"{dir}\" \"{pwsh}\" -NoExit -Command \"{claudeCommand}\"",
                UseShellExecute = true,
            };

        Process.Start(psi);
    }

    /// <summary>
    /// PowerShell 7's install location moves between MSI and MSIX, so prefer the per-user
    /// execution-alias shim, which has no version in its path.
    /// </summary>
    private static string ResolvePwsh()
    {
        var shim = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft",
            "WindowsApps",
            "pwsh.exe");
        if (File.Exists(shim))
        {
            return shim;
        }

        const string msi = @"C:\Program Files\PowerShell\7\pwsh.exe";
        return File.Exists(msi) ? msi : "pwsh.exe";
    }

    private static string? ResolveWindowsTerminal()
    {
        var shim = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft",
            "WindowsApps",
            "wt.exe");
        return File.Exists(shim) ? shim : null;
    }
}
