using System;
using System.Diagnostics;
using System.Linq;
using GoClaudeExtension.Sessions;

// Console harness for the indexer the Command Palette extension uses. It shares the exact
// same source files, so anything wrong here is wrong in the extension.
//   dotnet run --project IndexProbe            list the 15 most recent sessions
//   dotnet run --project IndexProbe -- money    search
var query = string.Join(' ', args);

var sw = Stopwatch.StartNew();
SessionIndex.Shared.Refresh(force: args.Contains("--force"));
sw.Stop();

var all = SessionIndex.Shared.Sessions;
Console.WriteLine($"Indexed {all.Count} sessions in {sw.ElapsedMilliseconds} ms");
Console.WriteLine($"Cache: {SessionIndex.CachePath}");
Console.WriteLine($"Missing cwd: {all.Count(s => s.Cwd.Length == 0)}   folder-not-on-disk: {all.Count(s => s.Cwd.Length > 0 && !System.IO.Directory.Exists(s.Cwd))}");
Console.WriteLine();

var matches = SessionSearch.Filter(all, query.Replace("--force", string.Empty).Trim(), 15);
foreach (var s in matches)
{
    var where = s.IsRemote ? $"ssh:{GoClaudeExtension.Sessions.RemoteHosts.Resolve(s) ?? "unknown"}" : "local";
    Console.WriteLine($"{s.LastActivityUtc.ToLocalTime():yyyy-MM-dd HH:mm}  {s.FolderName,-28} {Trim(s.Title, 70)}");
    Console.WriteLine($"    [{where}] {s.Cwd}  [{s.GitBranch}]  {s.UserMessages} msgs  blob={s.SearchBlob.Length}");
}

static string Trim(string text, int max) => text.Length <= max ? text : text[..(max - 1)] + "…";
