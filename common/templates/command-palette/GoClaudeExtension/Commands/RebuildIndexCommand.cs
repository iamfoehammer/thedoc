using System;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;
using GoClaudeExtension.Sessions;

namespace GoClaudeExtension.Commands;

/// <summary>Re-parses every transcript, ignoring the cache. Only needed if the cache goes stale.</summary>
internal sealed partial class RebuildIndexCommand : InvokableCommand
{
    public RebuildIndexCommand()
    {
        Name = "Rebuild session index";
        Id = "go.claude.rebuild";
        Icon = new IconInfo("\uE72C");
    }

    public override CommandResult Invoke()
    {
        try
        {
            SessionIndex.Shared.Refresh(force: true);
            return CommandResult.ShowToast($"Indexed {SessionIndex.Shared.Sessions.Count} sessions");
        }
        catch (Exception ex)
        {
            return CommandResult.ShowToast($"Index failed: {ex.Message}");
        }
    }
}
