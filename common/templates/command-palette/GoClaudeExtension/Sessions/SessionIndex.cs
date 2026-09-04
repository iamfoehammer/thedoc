using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace GoClaudeExtension.Sessions;

/// <summary>
/// Keeps the parsed view of ~/.claude/projects. Parsing every transcript takes a second or two
/// (some are 40 MB), so results are cached on disk and only re-parsed when a file's size or
/// timestamp changes.
/// </summary>
internal sealed class SessionIndex
{
    public static readonly SessionIndex Shared = new();

    private readonly object _gate = new();
    private List<SessionInfo> _sessions = new();
    private bool _cacheLoaded;

    public static string ProjectsRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".claude",
        "projects");

    public static string CachePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "go-claude-palette",
        // Bump this when SessionInfo gains a field, so old caches are rebuilt rather than
        // deserialised with the new field left at its default.
        "session-index.v2.json");

    public IReadOnlyList<SessionInfo> Sessions
    {
        get
        {
            lock (_gate)
            {
                return _sessions;
            }
        }
    }

    /// <summary>Loads the on-disk cache once, so the first paint is instant.</summary>
    public void EnsureCacheLoaded()
    {
        lock (_gate)
        {
            if (_cacheLoaded)
            {
                return;
            }

            _cacheLoaded = true;
            _sessions = ReadCache();
        }
    }

    /// <summary>Rescans the transcript folder, re-parsing only what changed.</summary>
    public void Refresh(bool force = false)
    {
        EnsureCacheLoaded();

        var known = Sessions.ToDictionary(s => s.FilePath, StringComparer.OrdinalIgnoreCase);
        var results = new List<SessionInfo>();
        var changed = force;

        if (Directory.Exists(ProjectsRoot))
        {
            foreach (var path in Directory.EnumerateFiles(ProjectsRoot, "*.jsonl", SearchOption.AllDirectories))
            {
                FileInfo file;
                try
                {
                    file = new FileInfo(path);
                    if (file.Length == 0)
                    {
                        continue;
                    }
                }
                catch (IOException)
                {
                    continue;
                }

                if (!force
                    && known.TryGetValue(path, out var cached)
                    && cached.FileSize == file.Length
                    && cached.FileTicks == file.LastWriteTimeUtc.Ticks
                    && cached.SessionId.Length > 0)
                {
                    results.Add(cached);
                    continue;
                }

                results.Add(SessionParser.Parse(file));
                changed = true;
            }
        }

        if (results.Count != known.Count)
        {
            changed = true;
        }

        results.Sort((a, b) => b.LastActivityUtc.CompareTo(a.LastActivityUtc));

        lock (_gate)
        {
            _sessions = results;
        }

        if (changed)
        {
            WriteCache(results);
        }
    }

    private static List<SessionInfo> ReadCache()
    {
        try
        {
            if (!File.Exists(CachePath))
            {
                return new List<SessionInfo>();
            }

            using var stream = File.OpenRead(CachePath);
            return JsonSerializer.Deserialize<List<SessionInfo>>(stream) ?? new List<SessionInfo>();
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            return new List<SessionInfo>();
        }
    }

    private static void WriteCache(List<SessionInfo> sessions)
    {
        try
        {
            var dir = Path.GetDirectoryName(CachePath);
            if (!string.IsNullOrEmpty(dir))
            {
                Directory.CreateDirectory(dir);
            }

            var temp = CachePath + ".tmp";
            using (var stream = File.Create(temp))
            {
                JsonSerializer.Serialize(stream, sessions);
            }

            File.Move(temp, CachePath, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // A stale cache only costs a re-parse next time.
        }
    }
}
