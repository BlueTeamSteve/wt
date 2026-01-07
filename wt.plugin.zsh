# wt - Git Worktree + Claude workflow tool
# Oh My Zsh plugin
#
# Add 'wt' to your plugins array in ~/.zshrc:
#   plugins=(... wt)
#
# Configuration (add to .zshrc before plugins are loaded):
#   export WT_DIR="$HOME/coding/worktrees"

# Version
WT_VERSION="0.1.0"

# Configuration with default
: ${WT_DIR:="$HOME/coding/worktrees"}

wt() {
  case "$1" in
    n|new)       _wt_new "${@:2}" ;;
    g|go)        _wt_go "${@:2}" ;;
    l|ls|list)   _wt_list ;;
    pr)          _wt_pr "${@:2}" ;;
    rm|remove)   _wt_rm "${@:2}" ;;
    done)        _wt_done ;;
    v|version)   _wt_version ;;
    *)           _wt_help ;;
  esac
}

_wt_new() {
  local name="$1"
  local base="${2:-main}"

  if [[ -z "$name" ]]; then
    echo "Usage: wt new <branch-name> [base-branch]"
    return 1
  fi

  local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$repo_root" ]]; then
    echo "Error: Not in a git repository"
    return 1
  fi

  local repo_name=$(basename "$repo_root")
  local wt_path="${WT_DIR}/${repo_name}-${name}"

  mkdir -p "$WT_DIR"

  echo "Creating worktree: $wt_path"
  git worktree add -b "$name" "$wt_path" "$base" || return 1

  cd "$wt_path" || return 1

  # Copy entire .claude folder from source repo
  if [[ -d "$repo_root/.claude" ]]; then
    cp -r "$repo_root/.claude" ".claude"
    echo "✓ Copied .claude folder"
  fi

  # Copy .env files from source repo (these are typically gitignored)
  # Searches root and all subdirectories, preserving relative paths
  local env_copied=0
  while IFS= read -r env_file; do
    local rel_path="${env_file#$repo_root/}"
    local target_dir=$(dirname "$rel_path")
    if [[ "$target_dir" != "." ]]; then
      mkdir -p "$target_dir"
    fi
    cp "$env_file" "$rel_path"
    ((env_copied++))
  done < <(find "$repo_root" -name '.env*' -type f ! -path '*/node_modules/*' ! -path '*/.git/*' 2>/dev/null)
  if [[ $env_copied -gt 0 ]]; then
    echo "✓ Copied $env_copied .env file(s)"
  fi

  _wt_setup_deps

  echo "\n🤖 Launching Claude..."
  claude
}

_wt_setup_deps() {
  if [[ -f "pnpm-lock.yaml" ]]; then
    echo "📦 Installing deps with pnpm..."
    pnpm install
  elif [[ -f "yarn.lock" ]]; then
    echo "📦 Installing deps with yarn..."
    yarn install
  elif [[ -f "package-lock.json" ]]; then
    echo "📦 Installing deps with npm..."
    npm install
  elif [[ -f "pyproject.toml" ]]; then
    echo "🐍 Setting up Python with uv..."
    uv sync
    if [[ -d ".venv" ]]; then
      source .venv/bin/activate
      echo "✓ Activated .venv"
    fi
  elif [[ -f "requirements.txt" ]]; then
    echo "🐍 Installing Python deps..."
    uv pip install -r requirements.txt
  fi
}

_wt_go() {
  local name="$1"

  if [[ -z "$name" ]]; then
    echo "Usage: wt go <branch-name>"
    echo "\nAvailable worktrees:"
    _wt_list
    return 1
  fi

  local repo_name=$(_wt_get_repo_name)
  local wt_path="${WT_DIR}/${repo_name}-${name}"

  if [[ ! -d "$wt_path" ]]; then
    # Fallback: fuzzy match by branch suffix
    wt_path=$(find "$WT_DIR" -maxdepth 1 -type d -name "*-${name}" 2>/dev/null | head -1)
  fi

  if [[ -z "$wt_path" || ! -d "$wt_path" ]]; then
    echo "Error: Worktree '$name' not found"
    echo "\nAvailable worktrees:"
    _wt_list
    return 1
  fi

  cd "$wt_path"
  echo "📂 Switched to: $wt_path"
  _wt_activate_venv
}

_wt_list() {
  echo "📋 Worktrees in $WT_DIR:\n"

  if [[ ! -d "$WT_DIR" ]]; then
    echo "  (none)"
    return
  fi

  local count=0
  for wt in "$WT_DIR"/*(-/N); do
    if [[ -d "$wt/.git" || -f "$wt/.git" ]]; then
      local branch=$(git -C "$wt" branch --show-current 2>/dev/null)
      local name=$(basename "$wt")
      printf "  %-30s %s\n" "$name" "($branch)"
      ((count++))
    fi
  done

  if [[ $count -eq 0 ]]; then
    echo "  (none)"
  fi

  echo "\n📍 All git worktrees:"
  git worktree list 2>/dev/null || echo "  (not in a git repo)"
}

_wt_pr() {
  if ! git rev-parse --git-dir &>/dev/null; then
    echo "Error: Not in a git repository"
    return 1
  fi

  local branch=$(git branch --show-current)

  _wt_auto_commit || return 1

  echo "📤 Pushing $branch..."
  git push -u origin "$branch" || return 1

  _wt_create_pr "$branch"
}

# ============================================================================
# Shared Helper Functions
# ============================================================================

# Get the base branch (main or master)
_wt_get_base_branch() {
  git rev-parse --verify main &>/dev/null && echo "main" || echo "master"
}

# Get repo name from current git root
# Strips any worktree suffix (e.g., "repo-branch" -> "repo")
_wt_get_repo_name() {
  local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$repo_root" ]]; then
    local name=$(basename "$repo_root")
    echo "${name%%-*}"
  fi
}

# Activate Python venv if it exists
_wt_activate_venv() {
  if [[ -f ".venv/bin/activate" ]]; then
    source .venv/bin/activate
    echo "✓ Activated .venv"
  fi
}

# Stage and commit changes with Claude-generated message
# Args: $1 = fallback message (optional, defaults to "WIP changes")
# Returns: 0 if committed or nothing to commit, 1 on error
_wt_auto_commit() {
  local fallback="${1:-WIP changes}"

  local has_staged=$(git diff --cached --quiet; echo $?)
  local has_unstaged=$(git diff --quiet; echo $?)
  local has_untracked=$(git ls-files --others --exclude-standard | head -1)

  if [[ "$has_staged" -eq 0 && "$has_unstaged" -eq 0 && -z "$has_untracked" ]]; then
    return 0  # Nothing to commit
  fi

  echo "📝 Committing uncommitted changes..."
  git add -A

  local diff_for_commit=$(git diff --cached --stat)
  local commit_prompt="Generate a concise git commit message for these changes:

$diff_for_commit

Output only the commit message, no explanation. Max 72 chars for first line."

  local commit_msg=$(echo "$commit_prompt" | claude -p 2>/dev/null)
  if [[ -z "$commit_msg" ]]; then
    commit_msg="$fallback"
  fi

  git commit -m "$commit_msg" || return 1
  echo "✓ Committed: $commit_msg"
}

# Create PR with Claude-generated title and body
# Args: $1 = branch name
# Returns: 0 on success, 1 on error
_wt_create_pr() {
  local branch="$1"
  local base=$(_wt_get_base_branch)

  echo "\n🤖 Generating PR with Claude..."

  local commits=$(git log --oneline "$base"..HEAD 2>/dev/null)
  local diff_stat=$(git diff --stat "$base"..HEAD 2>/dev/null)

  local context="Branch: $branch

Commits:
$commits

Changes from $base:
$diff_stat"

  local prompt="Generate a GitHub PR title and body for this branch.

$context

Output format (exactly):
TITLE: <concise title, max 72 chars, no prefix like 'feat:'>
BODY:
<2-4 bullet points summarizing the changes>

Be concise and focus on what changed and why."

  local result=$(echo "$prompt" | claude -p 2>/dev/null)

  if [[ -z "$result" ]]; then
    echo "❌ Claude unavailable"
    return 1
  fi

  local pr_title=$(echo "$result" | grep -E "^TITLE:" | sed 's/^TITLE:[[:space:]]*//')
  local pr_body=$(echo "$result" | sed -n '/^BODY:/,$ p' | tail -n +2)

  if [[ -z "$pr_title" ]]; then
    pr_title="$branch"
  fi

  echo "🔗 Creating PR..."
  echo "   Title: $pr_title"

  gh pr create --title "$pr_title" --body "$pr_body"
}

# Get worktree info from current directory or branch name argument
# Sets: _wt_branch, _wt_path
# Returns: 0 on success, 1 on failure
_wt_get_worktree_info() {
  local name="$1"
  _wt_branch=""
  _wt_path=""

  if [[ -z "$name" ]]; then
    # Auto-detect from current directory
    local current=$(pwd)
    if [[ "$current" == "$WT_DIR"/* ]]; then
      local wt_dir_name="${current#$WT_DIR/}"
      wt_dir_name="${wt_dir_name%%/*}"
      _wt_path="${WT_DIR}/${wt_dir_name}"
      _wt_branch="${wt_dir_name#*-}"
      echo "📍 Detected worktree: $_wt_branch"
      return 0
    else
      return 1
    fi
  else
    # Find by branch name
    local repo_name=$(_wt_get_repo_name)
    _wt_path="${WT_DIR}/${repo_name}-${name}"
    if [[ ! -d "$_wt_path" ]]; then
      _wt_path=$(find "$WT_DIR" -maxdepth 1 -type d -name "*-${name}" 2>/dev/null | head -1)
    fi

    if [[ -z "$_wt_path" || ! -d "$_wt_path" ]]; then
      echo "Error: Worktree '$name' not found"
      return 1
    fi

    _wt_branch="$name"
    return 0
  fi
}

# Switch to main/master worktree
# Returns: 0 on success, 1 on failure
_wt_switch_to_main() {
  local main_wt=$(git worktree list | grep -E '\[(main|master)\]' | awk '{print $1}')
  if [[ -n "$main_wt" ]]; then
    cd "$main_wt"
    echo "📍 Switched to: $main_wt"
    return 0
  else
    # Fallback: first worktree that isn't current
    main_wt=$(git worktree list | head -1 | awk '{print $1}')
    if [[ -n "$main_wt" ]]; then
      cd "$main_wt"
      echo "📍 Switched to: $main_wt"
      return 0
    fi
    cd "$HOME"
    return 1
  fi
}

# Remove worktree and delete local branch
# Args: $1 = worktree path, $2 = branch name
_wt_cleanup_local() {
  local wt_path="$1"
  local branch="$2"

  if [[ -d "$wt_path" ]]; then
    echo "🗑️  Removing worktree: $wt_path"
    git worktree remove "$wt_path" --force 2>/dev/null
  fi

  echo "🌿 Deleting local branch: $branch"
  git branch -D "$branch" 2>/dev/null || echo "  (branch already deleted or merged)"
}

# Delete remote branch if it exists
# Args: $1 = branch name
_wt_delete_remote_branch() {
  local branch="$1"

  # Check if remote branch exists
  if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "$branch"; then
    echo "🗑️  Deleting remote branch: $branch"
    git push origin --delete "$branch" 2>/dev/null || true
  fi
}

# Check for uncommitted, staged, or unpushed changes
# Returns: 0 if dirty, 1 if clean
_wt_has_dirty_state() {
  local has_staged=$(git diff --cached --quiet 2>/dev/null; echo $?)
  local has_unstaged=$(git diff --quiet 2>/dev/null; echo $?)
  local has_untracked=$(git ls-files --others --exclude-standard 2>/dev/null | head -1)

  # Check for unpushed commits
  local upstream=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null)
  local has_unpushed=0
  if [[ -n "$upstream" ]]; then
    local unpushed_count=$(git rev-list --count @{upstream}..HEAD 2>/dev/null)
    [[ "$unpushed_count" -gt 0 ]] && has_unpushed=1
  else
    # No upstream, check if there are any commits not on main
    local base=$(_wt_get_base_branch)
    local unpushed_count=$(git rev-list --count "$base"..HEAD 2>/dev/null)
    [[ "$unpushed_count" -gt 0 ]] && has_unpushed=1
  fi

  if [[ "$has_staged" -ne 0 || "$has_unstaged" -ne 0 || -n "$has_untracked" ]]; then
    echo "⚠️  Uncommitted changes detected"
    return 0
  fi

  if [[ "$has_unpushed" -eq 1 ]]; then
    echo "⚠️  Unpushed commits detected"
    return 0
  fi

  return 1
}

# ============================================================================
# Main Functions
# ============================================================================

_wt_rm() {
  local force=0
  local name=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) force=1; shift ;;
      *) name="$1"; shift ;;
    esac
  done

  # Get worktree info
  if ! _wt_get_worktree_info "$name"; then
    echo "Usage: wt rm [branch-name] [--force]"
    echo "  (run inside a worktree to auto-detect, or specify branch name)"
    return 1
  fi

  local wt_path="$_wt_path"
  local branch="$_wt_branch"

  # Check dirty state (unless --force)
  if [[ $force -eq 0 ]]; then
    # Need to be in the worktree to check its state
    local original_dir=$(pwd)
    cd "$wt_path" 2>/dev/null

    if _wt_has_dirty_state; then
      echo -n "Continue anyway? [y/N] "
      read -r response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        cd "$original_dir"
        return 1
      fi
    fi
  fi

  # Switch to main if we're in the worktree being removed
  local current=$(pwd)
  if [[ "$current" == "$wt_path"* ]]; then
    _wt_switch_to_main
  fi

  # Delete remote branch if --force
  if [[ $force -eq 1 ]]; then
    _wt_delete_remote_branch "$branch"
  fi

  # Cleanup local worktree and branch
  _wt_cleanup_local "$wt_path" "$branch"
}

_wt_done() {
  # Must be run from inside a worktree
  if ! _wt_get_worktree_info; then
    echo "Error: Must be run from inside a worktree"
    return 1
  fi

  local wt_path="$_wt_path"
  local branch="$_wt_branch"

  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "Error: Already on $branch, nothing to merge"
    return 1
  fi

  _wt_auto_commit || return 1

  # Push to remote
  echo "📤 Pushing $branch..."
  git push -u origin "$branch" || return 1

  # Check if PR exists, create if not
  if ! gh pr view "$branch" &>/dev/null; then
    _wt_create_pr "$branch" || return 1
  else
    echo "✓ PR already exists"
  fi

  # Merge the PR
  echo "\n🔄 Merging PR for $branch..."
  if ! gh pr merge --squash; then
    echo "❌ PR merge failed. Check the PR status with: gh pr view"
    return 1
  fi
  echo "✅ PR merged!"

  # Delete remote branch
  _wt_delete_remote_branch "$branch"

  # Switch to main worktree
  _wt_switch_to_main
  git pull

  # Cleanup local worktree and branch
  _wt_cleanup_local "$wt_path" "$branch"

  echo "\n🎉 Done! Branch merged and cleaned up."
}

_wt_version() {
  echo "wt version $WT_VERSION"
}

_wt_help() {
  echo "wt - Git Worktree + Claude workflow (v$WT_VERSION)"
  cat << 'EOF'

Commands:
  wt new <name> [base]   Create worktree, install deps, launch Claude
                         Alias: wt n
                         Base defaults to 'main'

  wt go <name>           Switch to existing worktree
                         Alias: wt g

  wt list                List all worktrees
                         Alias: wt l, wt ls

  wt pr [title]          Push branch and create PR
                         Auto-fills from commits if no title

  wt rm [name] [-f]      Remove worktree and delete branch
                         Auto-detects current worktree if inside one
                         -f/--force: discard uncommitted/unpushed changes,
                                     delete remote branch

  wt done                Stage, commit, push, create PR (if needed),
                         merge PR, and cleanup worktree

  wt version             Show version number
                         Alias: wt v

Configuration:
  WT_DIR                 Where worktrees are created
                         Default: ~/coding/worktrees

Examples:
  wt n fix-auth          Create worktree for fix-auth branch
  wt n experiment dev    Branch from dev instead of main
  wt g fix-auth          Switch to fix-auth worktree
  wt pr "Fix login bug"  Create PR with title
  wt done                Merge and cleanup when finished
EOF
}
