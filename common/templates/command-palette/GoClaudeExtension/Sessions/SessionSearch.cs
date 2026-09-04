using System;
using System.Collections.Generic;
using System.Linq;

namespace GoClaudeExtension.Sessions;

/// <summary>Ranks sessions against a query. Every whitespace-separated token must match somewhere.</summary>
internal static class SessionSearch
{
    public const int MaxResults = 60;

    public static List<SessionInfo> Filter(IReadOnlyList<SessionInfo> sessions, string query, int limit = MaxResults)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return sessions.Take(limit).ToList();
        }

        var tokens = query.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var scored = new List<(SessionInfo Session, int Score)>();

        foreach (var session in sessions)
        {
            var total = 0;
            var matchedAll = true;
            foreach (var token in tokens)
            {
                var score = ScoreToken(session, token);
                if (score == 0)
                {
                    matchedAll = false;
                    break;
                }

                total += score;
            }

            if (matchedAll)
            {
                scored.Add((session, total));
            }
        }

        return scored
            .OrderByDescending(x => x.Score)
            .ThenByDescending(x => x.Session.LastActivityUtc)
            .Take(limit)
            .Select(x => x.Session)
            .ToList();
    }

    private static int ScoreToken(SessionInfo session, string token)
    {
        if (session.SessionId.StartsWith(token, StringComparison.OrdinalIgnoreCase))
        {
            return 200;
        }

        if (Contains(session.Title, token))
        {
            return session.Title.StartsWith(token, StringComparison.OrdinalIgnoreCase) ? 130 : 100;
        }

        if (Contains(session.FolderName, token))
        {
            return 90;
        }

        if (Contains(session.Cwd, token))
        {
            return 60;
        }

        if (Contains(session.GitBranch, token))
        {
            return 40;
        }

        if (Contains(session.LastPrompt, token))
        {
            return 30;
        }

        if (Contains(session.SearchBlob, token))
        {
            return 15;
        }

        return 0;
    }

    private static bool Contains(string haystack, string needle) =>
        !string.IsNullOrEmpty(haystack) && haystack.Contains(needle, StringComparison.OrdinalIgnoreCase);
}
