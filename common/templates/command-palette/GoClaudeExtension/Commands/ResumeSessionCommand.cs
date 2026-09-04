using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;
using GoClaudeExtension.Sessions;

namespace GoClaudeExtension.Commands;

/// <summary>
/// Opens PowerShell in the session's folder and resumes the conversation, or SSHes to the
/// machine it belongs to when the session ran there.
/// </summary>
internal sealed partial class ResumeSessionCommand : InvokableCommand
{
    private readonly SessionInfo _session;

    public ResumeSessionCommand(SessionInfo session)
    {
        _session = session;
        Name = "Resume";
        Icon = new IconInfo("\uE768");
    }

    public override CommandResult Invoke() => SessionLauncher.Resume(_session);
}
