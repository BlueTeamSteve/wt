# wt

Git worktrees + Claude, sitting in a tree. K-I-S-S-I-N-G.

## What is this?

A tiny Oh My Zsh plugin that makes git worktrees ridiculously easy to use with Claude.

```bash
wt n fix-bug    # Create worktree, install deps, launch Claude
# ... vibe code with Claude ...
wt pr           # Claude writes your PR title & description
wt done         # Merge, cleanup, back to main. Ship it!
```

## Install

```bash
git clone https://github.com/BlueTeamSteve/wt.git ~/.oh-my-zsh/custom/plugins/wt
```

Add `wt` to your plugins in `~/.zshrc`:

```bash
plugins=(... wt)
```

Reload: `source ~/.zshrc`

## Commands

| Command | What it does |
|---------|--------------|
| `wt n <name>` | New worktree → install deps → launch Claude |
| `wt g <name>` | Go to worktree |
| `wt l` | List worktrees |
| `wt pr` | Claude writes PR, pushes, creates it |
| `wt rm <name>` | Remove worktree + branch |
| `wt done` | Merge PR + cleanup (the happy path) |

## Config

```bash
export WT_DIR="$HOME/coding/worktrees"  # Where worktrees live
```

## The Flow

```
wt n feature    →    work work work    →    wt pr    →    wt done
     ↓                                         ↓              ↓
 You're in a                            Claude writes    Merged! Clean!
 fresh worktree                         your PR for you  Back to main.
 with Claude ready
```

## Requirements

- [Oh My Zsh](https://ohmyz.sh/)
- [Claude CLI](https://github.com/anthropics/claude-code)
- [GitHub CLI](https://cli.github.com/) (`gh`)

## License

MIT. Go wild.
