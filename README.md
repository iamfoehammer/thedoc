# thedoc

**Emergency Medical Hologram for your LLM/CLI harnesses.**

A framework for creating dedicated "doctor" instances that diagnose, configure, and maintain your AI tool installations. Powered by Claude Code (with more engines coming).

> "Please state the nature of the CLI emergency."

## What It Does

You run `thedoc`, answer a few questions, and get a dedicated AI-powered doctor for your specific setup. The doctor knows how to:

- **Diagnose** issues with your AI tool configuration
- **Configure** settings, permissions, shell integrations, and SSH shortcuts
- **Maintain** health over time with an update mechanism that walks you through changes
- **Teach** you how your setup works so you can self-diagnose simple issues

## Supported Doctor Types

| Type | Status |
|------|--------|
| Claude Code | Supported |
| OpenClaw | Supported |
| Gemini CLI | Coming soon |

## Supported Engines (what powers the doctor)

| Engine | Status |
|--------|--------|
| Claude Code | Supported |
| OpenClaw | Coming soon |
| Gemini CLI | Coming soon |

## Quick Start

```bash
git clone https://github.com/iamfoehammer/thedoc.git ~/GitHub/thedoc
echo 'export PATH="$HOME/GitHub/thedoc:$PATH"' >> ~/.bashrc
source ~/.bashrc
thedoc
```

## Usage

```
thedoc              # Create a new doctor instance (or open setup)
thedoc setup        # Same as above
thedoc list         # List existing doctor instances
thedoc open <name>  # Open an existing instance directly
thedoc help         # Show help
```

## How It Works

### The Setup Flow

```
$ thedoc

  +==========================================+
  |   Emergency CLI Hologram activated       |
  +==========================================+

  Please state the nature of the CLI emergency.

  ...

  No emergency? Just a checkup? That's fine too.
  Contrary to my name, I handle everything from routine
  configuration to catastrophic meltdowns.

  What is this doctor for?
  [1] Claude Code
  [2] OpenClaw
  [3] Gemini CLI (not yet supported)

  Which LLM engine will power this doctor?
  [1] Claude Code

  Setup mode?
  [1] Quick - generate a starter config, refine later
  [2] Full  - interactive audit of your current setup
```

### What Gets Created

Running setup creates a new **instance folder** in your projects directory:

```
~/GitHub/claude-doctor/        # Your doctor instance
  CLAUDE.md                    # Personal config (your OS, known issues, etc.)
  DOCTOR.md                    # Shared brain (diagnostic logic, personality)
  .framework-updates           # Link to thedoc framework for updates
  .applied-updates             # Tracks which updates you've processed
```

### Staying Up To Date

```bash
cd ~/GitHub/thedoc && git pull
```

Next time you open your doctor instance, it checks for new updates and walks you through each one:

> "There's a new update about tmux copy/paste on WSL2. Here's what your
> current config looks like vs. what the update recommends. Want me to apply it?"

No merge conflicts. Your personal config (`CLAUDE.md`) is never touched by upstream.

## Included Templates

The framework ships with battle-tested templates in `common/templates/`:

- **tmux.conf** - WSL2-friendly config with working scroll, copy/paste (right-click to copy selection, right-click to paste), and sane defaults
- **generate-cc-aliases** - Auto-generates project shortcuts (`cc-*`, `cn-*`, `dcc-*`, `dcn-*`) for every folder in your projects directory
- **ssh-config-examples** - SSH shortcut patterns for quick access to remote machines

## Architecture

```
thedoc/                          # The framework (this repo)
  thedoc                         # Main command
  setup.sh                       # Interactive setup wizard
  doctors/
    claude-code/DOCTOR.md        # Claude Code doctor brain
    openclaw/DOCTOR.md           # OpenClaw doctor brain
    gemini/DOCTOR.md             # Stub
  engines/
    claude-code.sh               # Launches Claude Code
  common/
    templates/                   # Config templates
    skills/                      # Reusable skills

~/GitHub/claude-doctor/          # An instance (created by setup)
~/GitHub/openclaw-doctor/        # Another instance
```

The framework and instances are separate. You `git pull` the framework, your instances pick up updates through DOCTOR.md instructions. No conflicts.

## Why "The Doc"?

Named after the Emergency Medical Hologram from Star Trek: Voyager - an AI doctor activated in emergencies to diagnose and fix problems. Brilliant, occasionally exasperated, and always gets the job done.

Never seen it? [This clip explains everything.](https://youtu.be/Rn1QP9oL5V0?si=0PWFr6UhoIO_APdt)

## Contributing

Want to add support for a new doctor type or engine? The framework is designed to be extended:

- **New doctor type:** Add a `DOCTOR.md` to `doctors/<your-type>/`
- **New engine:** Add a launcher script to `engines/<your-engine>.sh`
- **New templates:** Add to `common/templates/`

PRs welcome.

## License

MIT
