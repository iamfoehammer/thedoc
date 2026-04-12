---
description: Regenerate cc-/cn-/dcc-/dcn- project aliases from the projects directory
allowed-tools: Bash
---

Do these steps in order:

1. Find the alias generator script. Check these locations:
   - `~/.local/bin/generate-cc-aliases`
   - The `common/templates/generate-cc-aliases` file in the doc framework repo
   If neither exists, tell the user the generator isn't installed yet and offer to set it up.

2. Run the generator script.

3. Run `grep '^alias ' ~/.cc-project-aliases | grep -oP '(?<=alias )\S+' | sort -u` to list all generated alias names.

4. Report a short summary: which projects were found, how many aliases were generated, and remind the user to open a new shell (or run `source ~/.cc-project-aliases`) for the aliases to take effect.
