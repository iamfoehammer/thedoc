using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;
using GoClaudeExtension.Commands;
using GoClaudeExtension.Pages;

namespace GoClaudeExtension;

public partial class GoClaudeCommandsProvider : CommandProvider
{
    /// <summary>How many "claude &lt;query&gt;" results appear inline at the top level.</summary>
    private const int InlineResultCount = 5;

    public GoClaudeCommandsProvider()
    {
        DisplayName = "Go - Claude Sessions";
        Icon = new IconInfo("\uE8BD");
        Id = "go.claude";
    }

    private readonly ICommandItem[] _commands =
    [
        new CommandItem(new SessionListPage())
        {
            Title = "Go - Claude Sessions",
            Subtitle = "Search and resume Claude Code conversations (alias: go)",
            Icon = new IconInfo("\uE8BD"),
        },
        new CommandItem(new RebuildIndexCommand())
        {
            Title = "Go - Rebuild session index",
            Subtitle = "Re-read every transcript in ~/.claude/projects",
            Icon = new IconInfo("\uE72C"),
        },
    ];

    private readonly IFallbackCommandItem[] _fallbacks = BuildFallbacks();

    public override ICommandItem[] TopLevelCommands() => _commands;

    public override IFallbackCommandItem[] FallbackCommands() => _fallbacks;

    private static IFallbackCommandItem[] BuildFallbacks()
    {
        var items = new IFallbackCommandItem[InlineResultCount];
        for (var i = 0; i < InlineResultCount; i++)
        {
            items[i] = new ClaudeSessionFallback(i);
        }

        return items;
    }
}
