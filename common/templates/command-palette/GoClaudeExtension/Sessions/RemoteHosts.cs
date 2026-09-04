using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace GoClaudeExtension.Sessions;

/// <summary>
/// Works out which machine an SSH session belongs to. The transcript never records the host,
/// so this guesses it from the remote home directory (/Users/tara -> tara) and only trusts
/// the guess when it is a real Host in ~/.ssh/config. An overrides file wins over both.
/// </summary>
internal static class RemoteHosts
{
    /// <summary>
    /// Optional map of session-folder name or cwd prefix to SSH host, e.g.
    /// { "ssh-176d21d8-...": "tara", "/srv/work": "buildbox" }.
    /// </summary>
    public static string OverridesPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "go-claude-palette",
        "ssh-hosts.json");

    private static readonly object Gate = new();
    private static Dictionary<string, string>? _overrides;
    private static HashSet<string>? _configHosts;
    private static DateTime _loadedUtc = DateTime.MinValue;

    /// <summary>Returns the SSH host for a session, or null when it cannot be worked out.</summary>
    public static string? Resolve(SessionInfo session)
    {
        if (!session.IsRemote)
        {
            return null;
        }

        EnsureLoaded();

        lock (Gate)
        {
            if (_overrides is { Count: > 0 })
            {
                if (_overrides.TryGetValue(session.ProjectDir, out var byFolder))
                {
                    return byFolder;
                }

                foreach (var (prefix, host) in _overrides)
                {
                    if (prefix.StartsWith('/') && session.Cwd.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    {
                        return host;
                    }
                }
            }

            var guess = GuessFromCwd(session.Cwd);
            if (guess is null)
            {
                return null;
            }

            return _configHosts is not null && _configHosts.Contains(guess) ? guess : null;
        }
    }

    /// <summary>/Users/tara/... or /home/jarvis/... -> the account name, which is usually the Host.</summary>
    private static string? GuessFromCwd(string cwd)
    {
        if (string.IsNullOrEmpty(cwd) || !cwd.StartsWith('/'))
        {
            return null;
        }

        var parts = cwd.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2)
        {
            return null;
        }

        return parts[0] is "Users" or "home" ? parts[1] : null;
    }

    private static void EnsureLoaded()
    {
        lock (Gate)
        {
            // Cheap enough to re-read now and then, so edits to either file take effect.
            if (DateTime.UtcNow - _loadedUtc < TimeSpan.FromSeconds(30))
            {
                return;
            }

            _loadedUtc = DateTime.UtcNow;
            _overrides = ReadOverrides();
            _configHosts = ReadSshConfigHosts();
        }
    }

    private static Dictionary<string, string> ReadOverrides()
    {
        try
        {
            if (!File.Exists(OverridesPath))
            {
                return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            }

            using var stream = File.OpenRead(OverridesPath);
            var parsed = JsonSerializer.Deserialize<Dictionary<string, string>>(stream);
            return parsed is null
                ? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                : new Dictionary<string, string>(parsed, StringComparer.OrdinalIgnoreCase);
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        }
    }

    private static HashSet<string> ReadSshConfigHosts()
    {
        var hosts = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var configPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".ssh",
            "config");

        try
        {
            if (!File.Exists(configPath))
            {
                return hosts;
            }

            foreach (var line in File.ReadLines(configPath))
            {
                var trimmed = line.Trim();
                if (!trimmed.StartsWith("Host ", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                // "Host wg wslGaming will-gaming" declares three aliases for one machine.
                foreach (var alias in trimmed[5..].Split(' ', StringSplitOptions.RemoveEmptyEntries))
                {
                    if (!alias.Contains('*') && !alias.Contains('?'))
                    {
                        hosts.Add(alias);
                    }
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // No config, no verified hosts; guesses will not be trusted.
        }

        return hosts;
    }
}
