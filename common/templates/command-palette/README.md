# Go - Claude Sessions for Command Palette

Type `go` then space in the Windows Command Palette and you drop into a list of every Claude
Code conversation on the machine, searchable by title, folder, git branch, or what was
actually said in it. Enter opens a PowerShell window in that conversation's folder and
resumes it.

Exactly the Window Walker pattern: `.` + space gives you windows, `go` + space gives you
sessions.

## The alias

The `go ` submenu comes from a Command Palette alias pointing at this extension's page:

```json
"go ": { "CommandId": "go.claude.sessions", "Alias": "go", "IsDirect": false }
```

`IsDirect: false` is what makes it wait for the space and pass the rest of what you type
through as the search. Install or repair it with `.\GoClaudeExtension\Install-Alias.ps1`
(it stops the palette first, since the palette rewrites `settings.json` on exit), or set it
by hand in Command Palette > Settings > Aliases.

There is a fallback too: typing `go <something>` or `claude <something>` at the top level
surfaces the five best matches inline, without the alias. That is the safety net; the alias
is the real path.

## Actions on a session (Ctrl+K)

| Action | What it does |
|--------|--------------|
| Resume (Enter) | `pwsh` in the session folder, running `claude --resume <id>` |
| New session in this folder | `pwsh` in the same folder, running `claude` |
| Open folder | Explorer, at the session's `cwd` |
| Copy resume command | `claude --resume <id>` to the clipboard |
| Copy folder path | the `cwd` to the clipboard |
| Rebuild session index | re-reads every transcript, ignoring the cache |

## SSH sessions

Claude Code writes transcripts for SSH sessions onto *your* machine, filed under
`~/.claude/projects/ssh-<sessionId>/` rather than an encoded local path, with a `cwd` like
`/Users/tara/Claude Projects` that does not exist here. Those show up marked `SSH: <host>`,
and Enter resumes them the only way that can work:

```
ssh -t <host> "cd '<remote cwd>' && claude --resume <id>"
```

The transcript never records which host it was, so the host is inferred from the remote home
directory (`/Users/tara` and `/home/jarvis` give `tara` and `jarvis`) and only used when it
matches a `Host` entry in `~/.ssh/config`. When it cannot be worked out, the session shows
`SSH: host unknown` and Enter tells you where to add a mapping:

`%LOCALAPPDATA%\go-claude-palette\ssh-hosts.json`

```json
{
  "ssh-176d21d8-63ee-4e66-906f-9cc0a6424f8b": "tara",
  "/srv/work": "buildbox"
}
```

Keys are either a session folder name or a `cwd` prefix. Overrides win over the guess.

A *local* session whose folder has since been deleted still shows `folder missing`; there is
nothing to resume into.

Set `GO_TERMINAL=wt` in your environment to open a Windows Terminal tab instead of a bare
PowerShell window.

## Build and install

Needs the .NET 9 SDK, Windows SDK 10.0.26100, Developer Mode on, and a code-signing
certificate whose subject matches `Publisher` in `Package.appxmanifest`. That defaults to
`CN=VDPin`; rename it to whatever you like, and the build script will tell you how to create
a matching certificate.

```powershell
cd GoClaudeExtension
.\build-msix.ps1
```

That publishes, packs an MSIX, signs it, removes any older install, and installs the new
one. Then reload the palette - `Start-Process x-cmdpal://reload`, or its own Reload command.

The script finds the certificate itself by matching the manifest's `Publisher` against
`Cert:\CurrentUser\My`; `-Thumbprint` or `$env:CMDPAL_SIGNING_THUMBPRINT` overrides that. If
there is no certificate, it prints the `New-SelfSignedCertificate` command to create one
(the `Import-Certificate` into `LocalMachine\TrustedPeople` needs an elevated shell).

## How it is put together

```
GoClaudeExtension/
  Program.cs                     COM server entry point
  GoClaudeExtension.cs           IExtension (GUID must match Package.appxmanifest)
  GoClaudeCommandsProvider.cs    top-level commands + the "claude " fallbacks
  Package.appxmanifest           MSIX manifest
  build-msix.ps1                 build, sign, pack, install
  Install-Alias.ps1              optional: wire the "claude " alias to the full page
  Sessions/
    SessionInfo.cs               one conversation
    SessionParser.cs             reads a .jsonl transcript
    SessionIndex.cs              scan + on-disk cache, re-parses only what changed
    SessionSearch.cs             ranking (title > folder > cwd > branch > content)
  Pages/SessionListPage.cs       the searchable page
  Commands/                      resume, new session, open folder, rebuild, fallback
IndexProbe/                      console harness that compiles the same Sessions/*.cs,
                                 so the parsing can be tested without the palette
```

Check the parser against your real transcripts without touching the palette:

```powershell
cd IndexProbe
dotnet run -- --force        # re-parse everything, list the 15 newest
dotnet run -- money manager  # try a search
```

## Gotchas worth remembering

- `Shmuelie.WinRTServer` must stay at 2.1.1; 2.2.1 changed the API.
- The manifest `Resource Language` must be `en-us`, not `x-generate`.
- The COM GUID appears in both `GoClaudeExtension.cs` and `Package.appxmanifest`.
- Command Palette rewrites `settings.json` when it exits, so `Install-Alias.ps1` stops it
  before editing.
- Transcripts have single lines running to tens of megabytes (tool output). The parser skips
  any line over 40 KB, since a prompt is never that big.
