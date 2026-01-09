#!/bin/bash

# Claude Code Status Line Installer

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "Installing Claude Code Status Line..."
echo ""

# Check dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "Warning: $1 is not installed. Some features may not work."
        echo "Install with: $2"
        echo ""
    fi
}

check_dependency "jq" "brew install jq (macOS) or apt-get install jq (Linux)"
check_dependency "bc" "brew install bc (macOS) or apt-get install bc (Linux)"

# Create .claude directory if it doesn't exist
if [ ! -d "$CLAUDE_DIR" ]; then
    echo "Creating $CLAUDE_DIR directory..."
    mkdir -p "$CLAUDE_DIR"
fi

# Copy status line script
echo "Copying statusline-command.sh to $CLAUDE_DIR..."
cp "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"

# Update settings.json
if [ -f "$SETTINGS_FILE" ]; then
    echo "Updating existing settings.json..."
    # Check if statusLine already exists
    if jq -e '.statusLine' "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo "statusLine config already exists in settings.json"
        echo "Current config:"
        jq '.statusLine' "$SETTINGS_FILE"
        echo ""
        read -p "Overwrite? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            jq '.statusLine = {"type": "command", "command": "~/.claude/statusline-command.sh"}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
            mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            echo "Updated statusLine config."
        else
            echo "Skipped settings update."
        fi
    else
        jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline-command.sh"}}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo "Added statusLine config to settings.json"
    fi
else
    echo "Creating new settings.json..."
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
EOF
fi

echo ""
echo "Installation complete!"
echo ""
echo "Restart Claude Code to see your new status line."
echo ""
echo "Status line elements:"
echo "  - Model name (blue)"
echo "  - Current directory (green)"
echo "  - Git branch (cyan)"
echo "  - Context window usage (color-coded)"
echo "  - Session duration (yellow)"
echo "  - API duration (cyan)"
echo "  - Code changes (+green/-red)"
echo "  - Token counts (white)"
echo "  - Session cost (magenta)"
echo "  - Weekly cost (cyan)"
