using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;

namespace GoClaudeExtension.Sessions;

/// <summary>Reads a session transcript and pulls out the handful of fields we search on.</summary>
internal static class SessionParser
{
    // Tool results and attachments run to megabytes on a single line. Nothing that big is a
    // prompt, so skip those lines instead of paying to parse them.
    private const int MaxParsedLineLength = 40_000;
    private const int MaxPromptLength = 300;
    private const int MaxBlobLength = 4_000;
    private const int HeadPrompts = 3;
    private const int TailPrompts = 12;

    /// <summary>Harness-injected wrappers that surround text the user never typed.</summary>
    private static readonly string[] WrapperTags =
    [
        "system-reminder",
        "command-name",
        "command-message",
        "command-args",
        "local-command-stdout",
        "local-command-stderr",
        "local-command-caveat",
        "user-prompt-submit-hook",
    ];

    /// <summary>Lines the harness writes into the user role that are not prompts.</summary>
    private static readonly string[] NoisePrefixes =
    [
        "Caveat:",
        "[Request interrupted",
        "API Error",
        "This session is being continued from a previous conversation",
    ];

    public static SessionInfo Parse(FileInfo file)
    {
        var info = new SessionInfo
        {
            SessionId = Path.GetFileNameWithoutExtension(file.Name),
            FilePath = file.FullName,
            ProjectDir = file.Directory?.Name ?? string.Empty,
            FileSize = file.Length,
            FileTicks = file.LastWriteTimeUtc.Ticks,
            LastActivityUtc = file.LastWriteTimeUtc,
        };

        var prompts = new List<string>();
        string? aiTitle = null;
        string? lastPrompt = null;

        try
        {
            using var stream = new FileStream(file.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 1 << 16);
            using var reader = new StreamReader(stream, Encoding.UTF8);
            string? line;
            while ((line = reader.ReadLine()) != null)
            {
                if (line.Length < 10 || line[0] != '{')
                {
                    continue;
                }

                try
                {
                    if (line.Contains("\"type\":\"ai-title\"", StringComparison.Ordinal))
                    {
                        aiTitle = ReadString(line, "aiTitle") ?? aiTitle;
                    }
                    else if (line.Contains("\"type\":\"last-prompt\"", StringComparison.Ordinal))
                    {
                        lastPrompt = ReadString(line, "lastPrompt") ?? lastPrompt;
                    }
                    else if (line.Length <= MaxParsedLineLength)
                    {
                        ReadMessageLine(line, info, prompts);
                    }
                }
                catch (JsonException)
                {
                    // A half-written line in a live session is not worth failing the file over.
                }
            }
        }
        catch (IOException)
        {
            // File vanished or is locked; keep whatever we got.
        }

        // Claude Code files SSH sessions under ssh-<sessionId> instead of an encoded local
        // path, and their cwd is a POSIX path on the remote box.
        info.IsRemote = info.ProjectDir.StartsWith("ssh-", StringComparison.OrdinalIgnoreCase)
            || info.Cwd.StartsWith('/');

        if (info.Cwd.Length == 0 && !info.IsRemote)
        {
            info.Cwd = DecodeProjectDir(info.ProjectDir);
        }

        info.FolderName = LeafOf(info.Cwd);
        info.UserMessages = prompts.Count;

        var cleanTitle = Clean(aiTitle);
        info.Title = cleanTitle.Length > 0
            ? cleanTitle
            : prompts.Count > 0
                ? Truncate(prompts[0], 90)
                : info.FolderName + " session";

        var cleanLast = Clean(lastPrompt);
        info.LastPrompt = cleanLast.Length > 0
            ? Truncate(cleanLast, MaxPromptLength)
            : prompts.Count > 0
                ? prompts[prompts.Count - 1]
                : string.Empty;

        info.SearchBlob = BuildBlob(prompts);
        return info;
    }

    private static void ReadMessageLine(string line, SessionInfo info, List<string> prompts)
    {
        var wantsCwd = info.Cwd.Length == 0 && line.Contains("\"cwd\"", StringComparison.Ordinal);
        var wantsBranch = info.GitBranch.Length == 0 && line.Contains("\"gitBranch\"", StringComparison.Ordinal);
        var isUser = line.Contains("\"role\":\"user\"", StringComparison.Ordinal);

        if (!wantsCwd && !wantsBranch && !isUser)
        {
            return;
        }

        using var doc = JsonDocument.Parse(line);
        var root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
        {
            return;
        }

        if (wantsCwd && root.TryGetProperty("cwd", out var cwd) && cwd.ValueKind == JsonValueKind.String)
        {
            info.Cwd = cwd.GetString() ?? string.Empty;
        }

        if (wantsBranch && root.TryGetProperty("gitBranch", out var branch) && branch.ValueKind == JsonValueKind.String)
        {
            info.GitBranch = branch.GetString() ?? string.Empty;
        }

        if (!isUser
            || !root.TryGetProperty("type", out var type)
            || type.ValueKind != JsonValueKind.String
            || type.GetString() != "user"
            || !root.TryGetProperty("message", out var message))
        {
            return;
        }

        var text = Clean(ExtractText(message));
        if (text.Length == 0)
        {
            return;
        }

        prompts.Add(Truncate(text, MaxPromptLength));
    }

    private static string ExtractText(JsonElement message)
    {
        if (message.ValueKind != JsonValueKind.Object || !message.TryGetProperty("content", out var content))
        {
            return string.Empty;
        }

        if (content.ValueKind == JsonValueKind.String)
        {
            return content.GetString() ?? string.Empty;
        }

        if (content.ValueKind != JsonValueKind.Array)
        {
            return string.Empty;
        }

        var sb = new StringBuilder();
        foreach (var block in content.EnumerateArray())
        {
            if (block.ValueKind == JsonValueKind.Object
                && block.TryGetProperty("type", out var blockType)
                && blockType.ValueKind == JsonValueKind.String
                && blockType.GetString() == "text"
                && block.TryGetProperty("text", out var textEl)
                && textEl.ValueKind == JsonValueKind.String)
            {
                sb.Append(textEl.GetString()).Append(' ');
            }
        }

        return sb.ToString();
    }

    private static string? ReadString(string line, string property)
    {
        using var doc = JsonDocument.Parse(line);
        return doc.RootElement.ValueKind == JsonValueKind.Object
            && doc.RootElement.TryGetProperty(property, out var el)
            && el.ValueKind == JsonValueKind.String
            ? el.GetString()
            : null;
    }

    /// <summary>Strips harness-injected wrappers and collapses whitespace.</summary>
    private static string Clean(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return string.Empty;
        }

        var text = raw;
        foreach (var tag in WrapperTags)
        {
            text = StripBetween(text, "<" + tag + ">", "</" + tag + ">");
        }

        var sb = new StringBuilder(text.Length);
        var lastWasSpace = false;
        foreach (var c in text)
        {
            if (char.IsWhiteSpace(c))
            {
                if (!lastWasSpace && sb.Length > 0)
                {
                    sb.Append(' ');
                }

                lastWasSpace = true;
            }
            else
            {
                sb.Append(c);
                lastWasSpace = false;
            }
        }

        var result = sb.ToString().Trim();
        foreach (var noise in NoisePrefixes)
        {
            if (result.StartsWith(noise, StringComparison.OrdinalIgnoreCase))
            {
                return string.Empty;
            }
        }

        return result;
    }

    private static string StripBetween(string text, string open, string close)
    {
        while (true)
        {
            var start = text.IndexOf(open, StringComparison.OrdinalIgnoreCase);
            if (start < 0)
            {
                return text;
            }

            var end = text.IndexOf(close, start, StringComparison.OrdinalIgnoreCase);
            text = end < 0
                ? text.Substring(0, start)
                : text.Substring(0, start) + text.Substring(end + close.Length);
        }
    }

    private static string BuildBlob(List<string> prompts)
    {
        var picked = new SortedSet<int>();
        for (var i = 0; i < prompts.Count && i < HeadPrompts; i++)
        {
            picked.Add(i);
        }

        for (var i = Math.Max(0, prompts.Count - TailPrompts); i < prompts.Count; i++)
        {
            picked.Add(i);
        }

        var sb = new StringBuilder();
        foreach (var i in picked)
        {
            if (sb.Length >= MaxBlobLength)
            {
                break;
            }

            sb.Append(prompts[i]).Append('\n');
        }

        return Truncate(sb.ToString(), MaxBlobLength);
    }

    private static string Truncate(string text, int max) =>
        text.Length <= max ? text : text.Substring(0, max);

    private static string LeafOf(string path)
    {
        if (string.IsNullOrEmpty(path))
        {
            return string.Empty;
        }

        var trimmed = path.TrimEnd('\\', '/');
        var idx = trimmed.LastIndexOfAny(new[] { '\\', '/' });
        return idx >= 0 ? trimmed.Substring(idx + 1) : trimmed;
    }

    /// <summary>
    /// Best-effort reverse of Claude's path encoding (C:\GitHub\go becomes C--GitHub-go).
    /// The encoding is lossy because folder names contain hyphens, so walk the filesystem
    /// greedily and only fall back to a naive join when nothing on disk matches.
    /// </summary>
    public static string DecodeProjectDir(string encoded)
    {
        if (string.IsNullOrEmpty(encoded) || encoded.Length < 3)
        {
            return string.Empty;
        }

        var sepIndex = encoded.IndexOf("--", StringComparison.Ordinal);
        if (sepIndex <= 0)
        {
            return encoded.Replace('-', Path.DirectorySeparatorChar);
        }

        var current = encoded.Substring(0, sepIndex) + ":\\";
        var parts = encoded.Substring(sepIndex + 2).Split('-', StringSplitOptions.RemoveEmptyEntries);
        var i = 0;
        while (i < parts.Length)
        {
            var matched = false;
            for (var take = parts.Length - i; take >= 1; take--)
            {
                var candidate = Path.Combine(current, string.Join("-", parts, i, take));
                if (Directory.Exists(candidate))
                {
                    current = candidate;
                    i += take;
                    matched = true;
                    break;
                }
            }

            if (!matched)
            {
                return Path.Combine(current, string.Join("-", parts, i, parts.Length - i));
            }
        }

        return current;
    }
}
