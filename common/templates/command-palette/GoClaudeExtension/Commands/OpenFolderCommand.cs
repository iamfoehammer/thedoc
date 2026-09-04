using System;
using System.Diagnostics;
using System.IO;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;
using GoClaudeExtension.Sessions;

namespace GoClaudeExtension.Commands;

/// <summary>Opens the session's working directory in Explorer.</summary>
internal sealed partial class OpenFolderCommand : InvokableCommand
{
    private readonly SessionInfo _session;

    public OpenFolderCommand(SessionInfo session)
    {
        _session = session;
        Name = "Open folder";
        Icon = new IconInfo("\uE838");
    }

    public override CommandResult Invoke()
    {
        if (!Directory.Exists(_session.Cwd))
        {
            return CommandResult.ShowToast($"Folder is gone: {_session.Cwd}");
        }

        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{_session.Cwd}\"") { UseShellExecute = true });
            return CommandResult.Dismiss();
        }
        catch (Exception ex)
        {
            return CommandResult.ShowToast($"Could not open folder: {ex.Message}");
        }
    }
}
