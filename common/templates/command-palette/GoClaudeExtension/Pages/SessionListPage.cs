using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;
using GoClaudeExtension.Commands;
using GoClaudeExtension.Sessions;

namespace GoClaudeExtension.Pages;

/// <summary>Searchable list of every Claude Code conversation on this machine.</summary>
internal sealed partial class SessionListPage : DynamicListPage
{
    private bool _refreshing;

    public SessionListPage()
    {
        Icon = new IconInfo("\uE8BD");
        Title = "Claude Sessions";
        Name = "Claude";
        Id = "go.claude.sessions";
        PlaceholderText = "Search by title, folder, branch, or what was said...";
        ShowDetails = true;

        SessionIndex.Shared.EnsureCacheLoaded();
        StartRefresh();
    }

    public override void UpdateSearchText(string oldSearch, string newSearch) => RaiseItemsChanged();

    public override IListItem[] GetItems()
    {
        var sessions = SessionIndex.Shared.Sessions;
        var matches = SessionSearch.Filter(sessions, SearchText ?? string.Empty);

        if (matches.Count == 0)
        {
            return
            [
                new ListItem(new RebuildIndexCommand())
                {
                    Title = sessions.Count == 0 ? "No sessions indexed yet" : "No matching sessions",
                    Subtitle = sessions.Count == 0
                        ? $"Looked in {SessionIndex.ProjectsRoot}"
                        : $"{sessions.Count} sessions indexed - try a different word",
                },
            ];
        }

        return matches.Select(CreateItem).ToArray();
    }

    /// <summary>Builds the list item for one session. Shared with the "claude " fallback.</summary>
    public static ListItem CreateItem(SessionInfo session)
    {
        var host = RemoteHosts.Resolve(session);
        var parts = new List<string>();

        if (session.IsRemote)
        {
            parts.Add(host is null ? "SSH: host unknown" : $"SSH: {host}");
        }

        if (session.FolderName.Length > 0)
        {
            parts.Add(session.FolderName);
        }

        if (session.GitBranch.Length > 0)
        {
            parts.Add(session.GitBranch);
        }

        parts.Add(Ago(session.LastActivityUtc));
        parts.Add($"{session.UserMessages} msg{(session.UserMessages == 1 ? string.Empty : "s")}");

        // A local session whose folder has been deleted cannot be resumed at all.
        if (!session.IsRemote && session.Cwd.Length > 0 && !System.IO.Directory.Exists(session.Cwd))
        {
            parts.Add("folder missing");
        }

        var moreCommands = new List<CommandContextItem>();
        if (!session.IsRemote)
        {
            moreCommands.Add(new CommandContextItem(new NewSessionCommand(session)));
            moreCommands.Add(new CommandContextItem(new OpenFolderCommand(session)));
        }

        moreCommands.Add(new CommandContextItem(new CopyTextCommand(SessionLauncher.ResumeCommand(session))
        {
            Name = "Copy resume command",
        }));
        moreCommands.Add(new CommandContextItem(new CopyTextCommand(session.Cwd) { Name = "Copy folder path" }));
        moreCommands.Add(new CommandContextItem(new RebuildIndexCommand()));

        return new ListItem(new ResumeSessionCommand(session))
        {
            Title = session.Title,
            Subtitle = string.Join(" | ", parts),
            Icon = new IconInfo(session.IsRemote ? "\uE774" : "\uE8BD"),
            MoreCommands = moreCommands.ToArray(),
            Details = new Details
            {
                Title = session.Title,
                Body = BuildDetails(session),
            },
        };
    }

    private static string BuildDetails(SessionInfo session)
    {
        var body = string.Empty;
        if (session.IsRemote)
        {
            var host = RemoteHosts.Resolve(session);
            body += host is null
                ? $"**Remote session**  \nNo SSH host known. Map it in `{RemoteHosts.OverridesPath}`\n\n"
                : $"**Remote session**  \nssh {host}\n\n";
        }

        body += $"**Folder**  \n{session.Cwd}\n\n";
        if (session.GitBranch.Length > 0)
        {
            body += $"**Branch**  \n{session.GitBranch}\n\n";
        }

        body += $"**Last active**  \n{session.LastActivityUtc.ToLocalTime():ddd d MMM yyyy, h:mm tt}\n\n";
        if (session.LastPrompt.Length > 0)
        {
            body += $"**Last prompt**  \n{session.LastPrompt}\n\n";
        }

        body += $"**Session**  \n`{SessionLauncher.ResumeCommand(session)}`";
        return body;
    }

    private void StartRefresh()
    {
        if (_refreshing)
        {
            return;
        }

        _refreshing = true;
        IsLoading = true;
        _ = Task.Run(() =>
        {
            try
            {
                SessionIndex.Shared.Refresh();
            }
            catch (Exception)
            {
                // Leave whatever the cache had; the rebuild command is there if it stays wrong.
            }
            finally
            {
                _refreshing = false;
                IsLoading = false;
                RaiseItemsChanged();
            }
        });
    }

    private static string Ago(DateTime utc)
    {
        var span = DateTime.UtcNow - utc;
        if (span.TotalMinutes < 1)
        {
            return "just now";
        }

        if (span.TotalMinutes < 60)
        {
            return $"{(int)span.TotalMinutes}m ago";
        }

        if (span.TotalHours < 24)
        {
            return $"{(int)span.TotalHours}h ago";
        }

        if (span.TotalDays < 30)
        {
            return $"{(int)span.TotalDays}d ago";
        }

        return utc.ToLocalTime().ToString("d MMM yyyy");
    }
}
