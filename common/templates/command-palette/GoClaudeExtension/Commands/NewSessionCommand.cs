using System;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;
using GoClaudeExtension.Sessions;

namespace GoClaudeExtension.Commands;

/// <summary>Opens PowerShell in the session's folder and starts a fresh conversation there.</summary>
internal sealed partial class NewSessionCommand : InvokableCommand
{
    private readonly SessionInfo _session;

    public NewSessionCommand(SessionInfo session)
    {
        _session = session;
        Name = "New session in this folder";
        Icon = new IconInfo("\uE710");
    }

    public override CommandResult Invoke()
    {
        try
        {
            TerminalLauncher.Launch(_session.Cwd, "claude");
            return CommandResult.Dismiss();
        }
        catch (Exception ex)
        {
            return CommandResult.ShowToast($"Could not start Claude: {ex.Message}");
        }
    }
}
