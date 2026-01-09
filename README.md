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
| Context Window | Color-coded | Used/free tokens (e.g., `22k/178k`) |
| Session Duration | Yellow | Time spent in session |
| API Duration | Cyan | Time spent on API calls |
| Code Changes | Green/Red | Lines added/removed (`+156 -23`) |
| Token Counts | White | Input/output tokens (`12k/3k`) |
| Session Cost | Magenta | Current session cost (`S:$0.42`) |
| Weekly Cost | Cyan | Rolling 7-day total (`W:$12.50`) |

### Context Window Color Coding
- **Green**: < 50% used
- **Yellow**: 50-75% used
- **Red**: > 75% used

## Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/claude-status-line.git

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

### Customizing Elements

Edit `~/.claude/statusline-command.sh` to customize what's displayed. Each element can be toggled by commenting out its section.

### Weekly Usage Tracking

The status line automatically tracks costs across sessions in `~/.claude/weekly-usage.json`. This file:
- Stores session costs with timestamps
- Auto-cleans entries older than 7 days
- Aggregates costs for the weekly total

## Example Output

```
Opus 4.5   |   my-project   |   [main]   |   22k/178k   |   5m 30s   |   API 45.2s   |   +156 -23   |   50k/8k   |   S:$0.55   |   W:$12.50
```

## Available Data Fields

The status line receives JSON data from Claude Code with these fields:

```json
{
  "model": { "display_name": "Claude 4.5 Opus" },
  "workspace": { "current_dir": "/path/to/project" },
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

## Troubleshooting

### Status line not appearing
1. Ensure the script is executable: `chmod +x ~/.claude/statusline-command.sh`
2. Check settings.json syntax is valid JSON
3. Restart Claude Code

### Missing data
Some fields (like `cost.total_cost_usd`) may not be available depending on your Claude Code version or authentication method.

### Weekly cost shows $0
The weekly tracking file may not exist yet. It will be created after your first session with the new status line.

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
