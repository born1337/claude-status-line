#!/bin/bash

# Claude Code Status Line Installer

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CONFIG_FILE="$CLAUDE_DIR/statusline.conf"
BIN_DIR="$HOME/.local/bin"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${CYAN}  Claude Code Status Line Installer${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# Check dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${YELLOW}Warning: $1 is not installed. Some features may not work.${RESET}"
        echo "Install with: $2"
        echo ""
    fi
}

check_dependency "jq" "brew install jq (macOS) or apt-get install jq (Linux)"
check_dependency "bc" "brew install bc (macOS) or apt-get install bc (Linux)"

# Create directories if they don't exist
if [ ! -d "$CLAUDE_DIR" ]; then
    echo "Creating $CLAUDE_DIR directory..."
    mkdir -p "$CLAUDE_DIR"
fi

if [ ! -d "$BIN_DIR" ]; then
    echo "Creating $BIN_DIR directory..."
    mkdir -p "$BIN_DIR"
fi

# Copy status line script
echo -e "${GREEN}Installing statusline-command.sh...${RESET}"
cp "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"

# Copy CLI config tool
echo -e "${GREEN}Installing statusline-config CLI tool...${RESET}"
cp "$SCRIPT_DIR/statusline-config" "$CLAUDE_DIR/statusline-config"
chmod +x "$CLAUDE_DIR/statusline-config"

# Create symlink in bin directory for easy access
if [ -d "$BIN_DIR" ]; then
    ln -sf "$CLAUDE_DIR/statusline-config" "$BIN_DIR/statusline-config"
    echo -e "${GREEN}Created symlink: $BIN_DIR/statusline-config${RESET}"
fi

# Copy default config file
echo -e "${GREEN}Installing default configuration...${RESET}"
cp "$SCRIPT_DIR/statusline.conf.default" "$CLAUDE_DIR/statusline.conf.default"

# Create config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    cp "$SCRIPT_DIR/statusline.conf.default" "$CONFIG_FILE"
    echo -e "${GREEN}Created config file: $CONFIG_FILE${RESET}"
else
    echo -e "${YELLOW}Config file already exists: $CONFIG_FILE${RESET}"
    echo "  (Use 'statusline-config reset' to reset to defaults)"
fi

# Update settings.json
if [ -f "$SETTINGS_FILE" ]; then
    echo ""
    echo "Updating existing settings.json..."
    if jq -e '.statusLine' "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo "statusLine config already exists in settings.json"
        echo "Current config:"
        jq '.statusLine' "$SETTINGS_FILE"
        echo ""
        read -p "Overwrite? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            jq '.statusLine = {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
            mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            echo -e "${GREEN}Updated statusLine config.${RESET}"
        else
            echo "Skipped settings update."
        fi
    else
        jq '. + {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo -e "${GREEN}Added statusLine config to settings.json${RESET}"
    fi
else
    echo "Creating new settings.json..."
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
EOF
    echo -e "${GREEN}Created settings.json${RESET}"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}Installation complete!${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo "Restart Claude Code to see your new status line."
echo ""
echo -e "${YELLOW}Configuration:${RESET}"
echo "  Edit:    ~/.claude/statusline.conf"
echo "  Or use:  statusline-config --help"
echo ""
echo -e "${YELLOW}Quick commands:${RESET}"
echo "  statusline-config show              # View current config"
echo "  statusline-config disable btc       # Hide BTC price"
echo "  statusline-config enable btc        # Show BTC price"
echo "  statusline-config color model red   # Change model color"
echo "  statusline-config reset             # Reset to defaults"
echo ""
echo -e "${YELLOW}Note:${RESET} If 'statusline-config' is not found, add ~/.local/bin to your PATH:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
