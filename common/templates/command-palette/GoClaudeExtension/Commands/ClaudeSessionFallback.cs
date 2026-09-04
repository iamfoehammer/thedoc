using System;
using System.Collections.Generic;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;
using GoClaudeExtension.Sessions;

namespace GoClaudeExtension.Commands;

/// <summary>
/// Puts session results straight into the top-level palette when the query starts with "go " or
/// "claude ". One instance shows one rank, so the provider registers several of these.
/// This is the safety net: the real path is the "go " alias, which opens the full page.
/// </summary>
internal sealed partial class ClaudeSessionFallback : FallbackCommandItem
{
    private static readonly string[] Prefixes = ["go ", "claude "];

    private readonly int _rank;
    private readonly ResumeFallbackCommand _command = new();

    public ClaudeSessionFallback(int rank)
        : base(string.Empty, string.Empty)
    {
        _rank = rank;
        Command = _command;
        Icon = new IconInfo("\uE8BD");
    }

    public override void UpdateQuery(string query)
    {
        var prefix = query is null
            ? null
            : Array.Find(Prefixes, p => query.StartsWith(p, StringComparison.OrdinalIgnoreCase));
        if (prefix is null)
        {
            Hide();
            return;
        }

        SessionIndex.Shared.EnsureCacheLoaded();
        var sessions = SessionIndex.Shared.Sessions;
        if (sessions.Count == 0)
        {
            Hide();
            return;
        }

        var search = query!.Substring(prefix.Length).Trim();
        var matches = SessionSearch.Filter(sessions, search, _rank + 1);
        if (matches.Count <= _rank)
        {
            Hide();
            return;
        }

        var session = matches[_rank];
        _command.Session = session;
        Title = session.Title;
        Subtitle = Describe(session);
    }

    private void Hide()
    {
        _command.Session = null;
        Title = string.Empty;
        Subtitle = string.Empty;
    }

    private static string Describe(SessionInfo session)
    {
        var host = RemoteHosts.Resolve(session);
        var parts = new List<string> { session.IsRemote ? $"Resume on {host ?? "unknown host"}" : "Resume" };
        if (session.FolderName.Length > 0)
        {
            parts.Add(session.FolderName);
        }

        if (session.GitBranch.Length > 0)
        {
            parts.Add(session.GitBranch);
        }

        parts.Add(session.LastActivityUtc.ToLocalTime().ToString("d MMM h:mm tt"));
        return string.Join(" | ", parts);
    }

    private sealed partial class ResumeFallbackCommand : InvokableCommand
    {
        public SessionInfo? Session { get; set; }

        public ResumeFallbackCommand()
        {
            Name = "Resume";
            Id = "go.claude.resume";
            Icon = new IconInfo("\uE768");
        }

        public override CommandResult Invoke() =>
            Session is null ? CommandResult.Dismiss() : SessionLauncher.Resume(Session);
    }
}
