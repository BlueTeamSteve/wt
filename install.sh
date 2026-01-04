#!/usr/bin/env bash
# Install wt - Git Worktree + Claude workflow tool (Oh My Zsh plugin)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OMZ_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
PLUGIN_DIR="$OMZ_CUSTOM/plugins/wt"
ZSHRC="$HOME/.zshrc"

echo "🚀 Installing wt Oh My Zsh plugin..."

# Check if Oh My Zsh is installed
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  echo "❌ Oh My Zsh not found at ~/.oh-my-zsh"
  echo ""
  echo "Install Oh My Zsh first:"
  echo "  sh -c \"\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
  echo ""
  echo "Or use standalone mode by sourcing directly:"
  echo "  source $SCRIPT_DIR/wt.plugin.zsh"
  exit 1
fi

# Create custom plugins directory if needed
mkdir -p "$OMZ_CUSTOM/plugins"

# Remove existing plugin (symlink or directory)
if [[ -L "$PLUGIN_DIR" || -d "$PLUGIN_DIR" ]]; then
  rm -rf "$PLUGIN_DIR"
  echo "✓ Removed existing wt plugin"
fi

# Create symlink to this directory
ln -s "$SCRIPT_DIR" "$PLUGIN_DIR"
echo "✓ Linked plugin to $PLUGIN_DIR"

# Create worktrees directory
mkdir -p "$HOME/coding/worktrees"
echo "✓ Created ~/coding/worktrees"

# Add wt to plugins array
if grep -qE "plugins=\([^)]*\bwt\b[^)]*\)" "$ZSHRC" 2>/dev/null; then
  echo "✓ 'wt' already in plugins array"
elif grep -qE "^plugins=\(" "$ZSHRC" 2>/dev/null; then
  # Add wt to existing plugins=(...)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/^plugins=(\(.*\))/plugins=(wt \1)/' "$ZSHRC"
  else
    sed -i 's/^plugins=(\(.*\))/plugins=(wt \1)/' "$ZSHRC"
  fi
  echo "✓ Added 'wt' to plugins array"
else
  echo "⚠️  No plugins=() found. Add manually to ~/.zshrc:"
  echo "  plugins=(wt)"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Reload your shell:"
echo "  source ~/.zshrc"
echo ""
echo "Then try:"
echo "  wt help"
echo "  wt n<TAB>     # Tab completion works!"
