# wt - Git Worktree + Claude CLI

Oh My Zsh plugin for managing git worktrees with Claude integration.

## Structure

- `wt.plugin.zsh` - Main plugin (all shell functions)
- `_wt` - Zsh tab completions
- `install.sh` - Symlinks to `~/.oh-my-zsh/custom/plugins/wt`

## Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `wt new <name> [base]` | `wt n` | Create worktree from main, install deps, run claude |
| `wt go <name>` | `wt g` | cd into existing worktree |
| `wt list` | `wt l` | List all worktrees |
| `wt pr [title]` | - | Push and create PR via gh |
| `wt rm [name]` | - | Remove worktree + branch (auto-detects if inside worktree) |
| `wt done` | - | Merge PR + cleanup |

## Config

```bash
export WT_DIR="$HOME/coding/worktrees"  # Default worktree location
```

## Dev Notes

- Pure zsh, no external dependencies (except git, gh, claude)
- Must be shell functions (not a binary) for simplicity
- Worktrees stored as `$WT_DIR/{repo}-{branch}/`
- Update _wt tab completions with every change
