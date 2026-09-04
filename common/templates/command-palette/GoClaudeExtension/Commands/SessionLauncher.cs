using System;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;
using GoClaudeExtension.Sessions;

namespace GoClaudeExtension.Commands;

/// <summary>Everything that knows how to get back into a session, local or over SSH.</summary>
internal static class SessionLauncher
{
    /// <summary>The command line that resumes a session, for launching or for the clipboard.</summary>
    public static string ResumeCommand(SessionInfo session)
    {
        if (!session.IsRemote)
        {
            return $"claude --resume {session.SessionId}";
        }

        var host = RemoteHosts.Resolve(session) ?? "<host>";
        return $"ssh -t {host} \"{RemoteCommand(session)}\"";
    }

    public static CommandResult Resume(SessionInfo session)
    {
        try
        {
            if (!session.IsRemote)
            {
                TerminalLauncher.Launch(session.Cwd, $"claude --resume {session.SessionId}");
                return CommandResult.Dismiss();
            }

            var host = RemoteHosts.Resolve(session);
            if (host is null)
            {
                return CommandResult.ShowToast(
                    $"No SSH host known for {session.Cwd}. Add one to {RemoteHosts.OverridesPath}");
            }

            // -t forces a TTY, which the Claude CLI needs on the far end.
            TerminalLauncher.Launch(null, $"ssh -t {host} \"{RemoteCommand(session)}\"");
            return CommandResult.Dismiss();
        }
        catch (Exception ex)
        {
            return CommandResult.ShowToast($"Could not resume: {ex.Message}");
        }
    }

    /// <summary>What the remote shell runs. Single quotes cope with spaces in the path.</summary>
    private static string RemoteCommand(SessionInfo session)
    {
        var resume = $"claude --resume {session.SessionId}";

        // A quote in the path would break the quoting; resuming from the home directory still
        // finds the session, it just starts somewhere else.
        return session.Cwd.Length == 0 || session.Cwd.Contains('\'')
            ? resume
            : $"cd '{session.Cwd}' && {resume}";
    }
}
