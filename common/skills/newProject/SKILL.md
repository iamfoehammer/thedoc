---
description: Create a new project folder and regenerate aliases
argument-hint: <project-name>
allowed-tools: Bash
---

The user wants to create a new project. The project name is: $ARGUMENTS

Do these steps in order:

1. Validate the project name: it should be lowercase, use hyphens for separators, and not start with `_` or `.`. If the name looks wrong, suggest a corrected version and ask before proceeding.

2. Determine the projects directory. Check CLAUDE.md for a "Projects dir" entry, or default to `~/GitHub/`.

3. Check if the project folder already exists. If it does, tell the user and stop.

4. Create the project folder with `mkdir`.

5. Look for the alias generator at `~/.local/bin/generate-cc-aliases`. If found, run it to regenerate aliases. If not found, skip this step and note that aliases aren't set up yet.

6. Report success with the new aliases available (if generated). Remind the user to run `source ~/.cc-project-aliases` or open a new shell for aliases to take effect.
