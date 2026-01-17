# CLAUDE.md

This file provides context for Claude Code when working on this project.

## Project Overview

This is a customizable status line script for Claude Code CLI that displays real-time metrics in the terminal.

## File Structure

```
claude-status-line/
├── statusline-command.sh    # Main status line script (bash)
├── install.sh               # Installation script
├── settings.example.json    # Example Claude Code settings
├── README.md                # Documentation
├── CLAUDE.md                # This file (Claude Code context)
├── LICENSE                  # MIT License
└── .gitignore               # Git ignore rules
```

## Key Files

### statusline-command.sh
- Main bash script that generates the status line
- Receives JSON input via stdin from Claude Code
- Outputs formatted text with ANSI colors
- Uses `ccusage` for weekly/lifetime cost tracking

### Key dependencies
- `jq` - JSON parsing
- `bc` - Arithmetic calculations
- `git` - Branch detection (optional)
- `ccusage` - Cost tracking (optional, install via npm)

## Common Tasks

### Testing the script
```bash
echo '{"model":{"display_name":"Claude 4.5 Opus"},"workspace":{"current_dir":"/test"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":15000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":2000},"total_input_tokens":22000,"total_output_tokens":3000},"cost":{"total_cost_usd":0.55,"total_duration_ms":156000,"total_api_duration_ms":23500,"total_lines_added":156,"total_lines_removed":23},"session_id":"test-123"}' | ./statusline-command.sh
# Output: Opus 4.5 | <hostname> | test | 22k/200k (11%) | 2m 36s | API 23.5s | +156 -23 | S:$0.550 | ...
```

### Adding new elements
1. Extract data from JSON input using `jq`
2. Format the display string with ANSI colors
3. Add to the final `printf` statement

### Color codes reference
- `\033[0;34m` - Blue
- `\033[0;32m` - Green
- `\033[0;36m` - Cyan
- `\033[0;33m` - Yellow
- `\033[0;31m` - Red
- `\033[0;35m` - Magenta
- `\033[0;37m` - White
- `\033[0m` - Reset

## Notes

- Status line updates every ~300ms when conversation changes
- Keep the script fast to avoid UI lag
- Cost data from ccusage is cached (60s default TTL) for performance
