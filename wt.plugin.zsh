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

  # Copy Claude settings from source repo
  if [[ -f "$repo_root/.claude/settings.local.json" ]]; then
    mkdir -p ".claude"
    cp "$repo_root/.claude/settings.local.json" ".claude/"
    echo "✓ Copied Claude settings"
  fi

  # Copy .env files from source repo (these are typically gitignored)
  local env_copied=0
  for env_file in "$repo_root"/.env*; do
    if [[ -f "$env_file" ]]; then
      local filename=$(basename "$env_file")
      cp "$env_file" "./$filename"
      ((env_copied++))
    fi
  done
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

  local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  local repo_name=""

  if [[ -n "$repo_root" ]]; then
    repo_name=$(basename "$repo_root")
    repo_name="${repo_name%%-*}"
  fi

  local wt_path="${WT_DIR}/${repo_name}-${name}"

  if [[ -d "$wt_path" ]]; then
    cd "$wt_path"
    echo "📂 Switched to: $wt_path"

    if [[ -f ".venv/bin/activate" ]]; then
      source .venv/bin/activate
      echo "✓ Activated .venv"
    fi
  else
    local found=$(find "$WT_DIR" -maxdepth 1 -type d -name "*-${name}" 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
      cd "$found"
      echo "📂 Switched to: $found"
      if [[ -f ".venv/bin/activate" ]]; then
        source .venv/bin/activate
      fi
    else
      echo "Error: Worktree '$name' not found"
      echo "\nAvailable worktrees:"
      _wt_list
      return 1
    fi
  fi
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

  # Find base branch (main or master)
  local base="main"
  if ! git rev-parse --verify main &>/dev/null; then
    base="master"
  fi

  # Check for uncommitted changes
  local has_staged=$(git diff --cached --quiet; echo $?)
  local has_unstaged=$(git diff --quiet; echo $?)

  if [[ "$has_staged" -ne 0 || "$has_unstaged" -ne 0 ]]; then
    echo "📝 Committing uncommitted changes..."

    # Stage everything
    git add -A

    # Get diff for commit message
    local diff_for_commit=$(git diff --cached --stat)

    local commit_prompt="Generate a concise git commit message for these changes:

$diff_for_commit

Output only the commit message, no explanation. Max 72 chars for first line."

    local commit_msg=$(echo "$commit_prompt" | claude -p 2>/dev/null)

    if [[ -z "$commit_msg" ]]; then
      echo "❌ Claude unavailable"
      return 1
    fi

    git commit -m "$commit_msg" || return 1
    echo "✓ Committed: $commit_msg"
  fi

  echo "\n🤖 Generating PR with Claude..."

  # Gather context for Claude
  local commits=$(git log --oneline "$base"..HEAD 2>/dev/null)
  local diff_stat=$(git diff --stat "$base"..HEAD 2>/dev/null)

  # Build context
  local context="Branch: $branch

Commits:
$commits

Changes from $base:
$diff_stat"

  # Generate PR title and body with Claude
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

  # Parse title and body from Claude's response
  local pr_title=$(echo "$result" | grep -E "^TITLE:" | sed 's/^TITLE:[[:space:]]*//')
  local pr_body=$(echo "$result" | sed -n '/^BODY:/,$ p' | tail -n +2)

  if [[ -z "$pr_title" ]]; then
    pr_title="$branch"
  fi

  echo "📤 Pushing $branch..."
  git push -u origin "$branch" || return 1

  echo "\n🔗 Creating PR..."
  echo "   Title: $pr_title"

  gh pr create --title "$pr_title" --body "$pr_body"
}

_wt_rm() {
  local name="$1"

  if [[ -z "$name" ]]; then
    echo "Usage: wt rm <branch-name>"
    return 1
  fi

  local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  local repo_name=""

  if [[ -n "$repo_root" ]]; then
    repo_name=$(basename "$repo_root")
    repo_name="${repo_name%%-*}"
  fi

  local wt_path="${WT_DIR}/${repo_name}-${name}"

  if [[ ! -d "$wt_path" ]]; then
    wt_path=$(find "$WT_DIR" -maxdepth 1 -type d -name "*-${name}" 2>/dev/null | head -1)
  fi

  if [[ -z "$wt_path" || ! -d "$wt_path" ]]; then
    echo "Error: Worktree '$name' not found"
    return 1
  fi

  local current=$(pwd)
  if [[ "$current" == "$wt_path"* ]]; then
    echo "📍 Returning to main repo..."
    local main_wt=$(git worktree list | grep -v "$wt_path" | head -1 | awk '{print $1}')
    if [[ -n "$main_wt" ]]; then
      cd "$main_wt"
    else
      cd "$HOME"
    fi
  fi

  echo "🗑️  Removing worktree: $wt_path"
  git worktree remove "$wt_path" --force

  echo "🌿 Deleting branch: $name"
  git branch -D "$name" 2>/dev/null || echo "  (branch may have been merged)"
}

_wt_done() {
  if ! git rev-parse --git-dir &>/dev/null; then
    echo "Error: Not in a git repository"
    return 1
  fi

  local branch=$(git branch --show-current)
  local current_wt=$(pwd)

  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "Error: Already on $branch, nothing to merge"
    return 1
  fi

  echo "🔄 Merging PR for $branch..."

  # Don't use --delete-branch as it tries to checkout main (fails with worktrees)
  if gh pr merge --squash; then
    echo "✅ PR merged!"

    # Delete remote branch manually
    echo "🗑️  Deleting remote branch..."
    git push origin --delete "$branch" 2>/dev/null || true

    # Switch to main worktree
    local main_wt=$(git worktree list | grep -E '\[(main|master)\]' | awk '{print $1}')
    if [[ -n "$main_wt" ]]; then
      cd "$main_wt"
      echo "📍 Switched to: $main_wt"
      git pull
    fi

    # Remove the feature worktree
    if [[ -d "$current_wt" && "$current_wt" != "$main_wt" ]]; then
      echo "🗑️  Removing worktree: $current_wt"
      git worktree remove "$current_wt" --force 2>/dev/null
    fi

    # Delete local branch
    git branch -D "$branch" 2>/dev/null || true

    echo "\n🎉 Done! Branch merged and cleaned up."
  else
    echo "❌ PR merge failed. Check the PR status with: gh pr view"
    return 1
  fi
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

  wt rm <name>           Remove worktree and delete branch

  wt done                Merge PR, delete branch, cleanup worktree

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
