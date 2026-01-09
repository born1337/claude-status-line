# Claude Code Status Line

A customizable status line for [Claude Code](https://claude.ai/code) that displays useful metrics at the bottom of your terminal.

![Status Line Example](./screenshot.png)

## Features

Display real-time information while using Claude Code:

| Element | Color | Description |
|---------|-------|-------------|
| Model | Blue | Current model (e.g., "Opus 4.5") |
| Directory | Green | Current working directory |
| Git Branch | Cyan | Active git branch `[main]` |
| Context Window | Color-coded | Used/free tokens (e.g., `141k/58k`) |
| Session Duration | Yellow | Time spent in session |
| API Duration | Cyan | Time spent on API calls |
| Code Changes | Green/Red | Lines added/removed (`+1453 -226`) |
| Session Cost | Magenta | Current session cost (`S:$13.0`) |
| Weekly Cost | Cyan | Rolling 7-day total (`W:$81.2`) |
| Lifetime Cost | White | All-time total (`L:$81.2`) |
| BTC Price | Yellow | Live Bitcoin price (`BTC:$90,387`) |

### Context Window Color Coding
- **Green**: < 50% used
- **Yellow**: 50-75% used
- **Red**: > 75% used

## Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/born1337/claude-status-line.git

# Run the install script
cd claude-status-line
./install.sh
```

### Manual Install

1. Copy the status line script:
```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

2. Add to your Claude Code settings (`~/.claude/settings.json`):
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

3. Restart Claude Code to see the status line.

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- `jq` for JSON parsing
- `bc` for cost calculations
- `git` (optional, for branch display)

### Install dependencies (macOS)
```bash
brew install jq bc
```

### Install dependencies (Ubuntu/Debian)
```bash
sudo apt-get install jq bc
```

## Configuration

The status line is fully configurable via CLI or config file.

### Using the CLI Tool

```bash
# View current configuration
statusline-config show

# Enable/disable elements
statusline-config disable btc       # Hide BTC price
statusline-config enable btc        # Show BTC price

# Change colors
statusline-config color model red
statusline-config color directory cyan

# Reset to defaults
statusline-config reset

# List all options
statusline-config list
```

### Config File

Edit `~/.claude/statusline.conf` directly:

```bash
# Elements (1=show, 0=hide)
SHOW_MODEL=1
SHOW_DIRECTORY=1
SHOW_GIT_BRANCH=1
SHOW_CONTEXT=1
SHOW_DURATION=1
SHOW_API_DURATION=1
SHOW_CODE_CHANGES=1
SHOW_SESSION_COST=1
SHOW_WEEKLY_COST=1
SHOW_LIFETIME_COST=1
SHOW_BTC=1

# Colors
COLOR_MODEL=blue
COLOR_DIRECTORY=green
COLOR_BTC=yellow
# ... and more

# Settings
BTC_CACHE_TTL=30
```

### Available Colors

`black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`
`bright_black`, `bright_red`, `bright_green`, `bright_yellow`, `bright_blue`, `bright_magenta`, `bright_cyan`, `bright_white`

## Usage Tracking

The status line tracks **comprehensive session data** in `~/.claude/usage-tracking.json`:

```json
{
  "sessions": [
    {
      "session_id": "abc-123-def-456",
      "timestamp": 1736450000,
      "model": "Claude 4.5 Opus",
      "project_dir": "/Users/example/myproject",
      "cost": 0.55,
      "duration_ms": 156000,
      "api_duration_ms": 23500,
      "input_tokens": 22000,
      "output_tokens": 3000,
      "lines_added": 156,
      "lines_removed": 23
    }
  ]
}
```

### What's Tracked Per Session
- Session ID & timestamp
- Model used
- Project directory
- Cost (USD)
- Duration (total & API time)
- Token usage (input/output)
- Lines of code changed

### Cost Calculations
| Metric | How It's Calculated |
|--------|---------------------|
| Session | Current session's `cost.total_cost_usd` |
| Weekly | Sum of sessions from last 7 days |
| Lifetime | Sum of all sessions ever |

### Data Retention
- **Sessions are never deleted** - full history is preserved
- Query any time range from the data
- Calculate custom metrics (by project, by model, etc.)

## Example Output

```
Opus 4.5 | claude-status-line | [feature/configurable-statusline] | 141k/58k | 3h 20m | API 23m 0s | +1453 -226 | S:$13.0 | W:$81.2 | L:$81.2 | BTC:$90,387
```

## Available Data Fields

The status line receives JSON data from Claude Code with these fields:

```json
{
  "model": { "display_name": "Claude 4.5 Opus" },
  "workspace": {
    "current_dir": "/path/to/project",
    "project_dir": "/path/to/project"
  },
  "session_id": "uuid",
  "context_window": {
    "context_window_size": 200000,
    "current_usage": { "input_tokens": 15000 },
    "total_input_tokens": 50000,
    "total_output_tokens": 8000
  },
  "cost": {
    "total_cost_usd": 0.55,
    "total_duration_ms": 330000,
    "total_api_duration_ms": 45200,
    "total_lines_added": 156,
    "total_lines_removed": 23
  }
}
```

## Querying Your Data

Since all sessions are stored, you can query your usage history:

```bash
# Total lifetime cost
jq '[.sessions[].cost] | add' ~/.claude/usage-tracking.json

# Sessions by project
jq '.sessions | group_by(.project_dir) | map({project: .[0].project_dir, total: ([.[].cost] | add)})' ~/.claude/usage-tracking.json

# Most expensive session
jq '.sessions | max_by(.cost)' ~/.claude/usage-tracking.json

# Total tokens used
jq '[.sessions[] | .input_tokens + .output_tokens] | add' ~/.claude/usage-tracking.json

# Usage by model
jq '.sessions | group_by(.model) | map({model: .[0].model, cost: ([.[].cost] | add)})' ~/.claude/usage-tracking.json
```

## Troubleshooting

### Status line not appearing
1. Ensure the script is executable: `chmod +x ~/.claude/statusline-command.sh`
2. Check settings.json syntax is valid JSON
3. Restart Claude Code

### Missing data
Some fields (like `cost.total_cost_usd`) may not be available depending on your Claude Code version or authentication method.

### Costs show $0
The tracking file may not exist yet. It will be created after your first session with the new status line.

## Contributing

Contributions welcome! Feel free to:
- Add new display elements
- Improve formatting/colors
- Fix bugs
- Add documentation

## License

MIT License - see [LICENSE](LICENSE) file.

## Credits

Created with Claude Code. Inspired by the need to monitor Claude usage at a glance.
