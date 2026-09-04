using System;

namespace GoClaudeExtension.Sessions;

/// <summary>One Claude Code conversation, as recorded in ~/.claude/projects/[project]/[sessionId].jsonl.</summary>
public sealed class SessionInfo
{
    public string SessionId { get; set; } = string.Empty;

    public string FilePath { get; set; } = string.Empty;

    /// <summary>Encoded folder name under ~/.claude/projects (e.g. C--GitHub-go).</summary>
    public string ProjectDir { get; set; } = string.Empty;

    /// <summary>Working directory the session ran in.</summary>
    public string Cwd { get; set; } = string.Empty;

    /// <summary>Leaf of Cwd, which is what people mean when they search by "folder".</summary>
    public string FolderName { get; set; } = string.Empty;

    public string GitBranch { get; set; } = string.Empty;

    /// <summary>
    /// True for sessions Claude Code ran over SSH on another machine. Their transcripts land
    /// here, but their folder is on the remote host, so they resume over SSH rather than in a
    /// local shell.
    /// </summary>
    public bool IsRemote { get; set; }

    /// <summary>The ai-title Claude wrote for the session, else its first prompt.</summary>
    public string Title { get; set; } = string.Empty;

    public string LastPrompt { get; set; } = string.Empty;

    /// <summary>Condensed prompt text, used for content search.</summary>
    public string SearchBlob { get; set; } = string.Empty;

    public int UserMessages { get; set; }

    public long FileSize { get; set; }

    public long FileTicks { get; set; }

    public DateTime LastActivityUtc { get; set; }
}
