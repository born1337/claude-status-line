#!/bin/bash

# =============================================================================
# Claude Code Status Line
# =============================================================================
#
# Display format:
#   Opus 4.5   |   test   |   [main]   |   22k/178k   |   2m 30s   |   API 2.3s   |   +156 -23   |   12k/3k   |   S:$0.42   |   W:$12.50
#
# Elements:
#   - Model name (blue)         - e.g., "Opus 4.5"
#   - Current directory (green) - folder name
#   - Git branch (cyan)         - shows [branch] when in a repo
#   - Context window (color-coded) - used/free tokens (green <50%, yellow 50-75%, red >75%)
#   - Session duration (yellow) - time spent in session
#   - API duration (cyan)       - time spent in API calls
#   - Code changes (green/red)  - lines added/removed
#   - Token counts (white)      - input/output tokens (e.g., 12k/3k)
#   - Session cost (magenta)    - S:$X.XX current session cost
#   - Weekly cost (cyan)        - W:$X.XX total cost this week
#
# =============================================================================

# Read JSON input from stdin
input=$(cat)

# Tracking file for weekly usage
TRACKING_FILE="$HOME/.claude/weekly-usage.json"
SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"')

# Extract basic info
model_name=$(echo "$input" | jq -r '.model.display_name')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')

# Simplify model name (e.g., "Claude 3.5 Sonnet" -> "Sonnet 3.5")
model_short=$(echo "$model_name" | sed -E 's/Claude ([0-9.]+) (Opus|Sonnet|Haiku)/\2 \1/')

# Get directory name
dir_name=$(basename "$current_dir")

# Get git branch (suppress errors and skip optional locks)
git_branch=""
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
    if [ -n "$git_branch" ]; then
        git_branch="   |   $(printf '\033[0;36m')[$git_branch]$(printf '\033[0m')"
    fi
fi

# Calculate context window usage (used/free tokens)
context_info=""
usage=$(echo "$input" | jq '.context_window.current_usage')
if [ "$usage" != "null" ]; then
    current=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    size=$(echo "$input" | jq '.context_window.context_window_size')
    free=$((size - current))
    pct=$((current * 100 / size))

    # Format token counts
    format_ctx_tokens() {
        local tokens=$1
        if [ "$tokens" -ge 1000000 ]; then
            echo "$(echo "scale=0; $tokens / 1000000" | bc)M"
        elif [ "$tokens" -ge 1000 ]; then
            echo "$(echo "scale=0; $tokens / 1000" | bc)k"
        else
            echo "$tokens"
        fi
    }

    used_fmt=$(format_ctx_tokens $current)
    free_fmt=$(format_ctx_tokens $free)

    # Color code based on usage
    if [ $pct -lt 50 ]; then
        color='\033[0;32m'  # Green
    elif [ $pct -lt 75 ]; then
        color='\033[0;33m'  # Yellow
    else
        color='\033[0;31m'  # Red
    fi
    context_info="   |   $(printf "${color}")${used_fmt}/${free_fmt}$(printf '\033[0m')"
fi

# Calculate session duration
duration_info=""
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // .duration_ms // 0')
if [ "$duration_ms" != "null" ] && [ "$duration_ms" -gt 0 ]; then
    total_secs=$((duration_ms / 1000))
    hours=$((total_secs / 3600))
    mins=$(( (total_secs % 3600) / 60 ))
    secs=$((total_secs % 60))

    if [ $hours -gt 0 ]; then
        duration_info="   |   $(printf '\033[0;33m')${hours}h ${mins}m$(printf '\033[0m')"
    elif [ $mins -gt 0 ]; then
        duration_info="   |   $(printf '\033[0;33m')${mins}m ${secs}s$(printf '\033[0m')"
    else
        duration_info="   |   $(printf '\033[0;33m')${secs}s$(printf '\033[0m')"
    fi
fi

# Calculate API duration
api_duration_info=""
api_duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
if [ "$api_duration_ms" != "null" ] && [ "$api_duration_ms" -gt 0 ]; then
    api_secs=$((api_duration_ms / 1000))
    api_ms=$((api_duration_ms % 1000))

    if [ $api_secs -ge 60 ]; then
        api_mins=$((api_secs / 60))
        api_remaining_secs=$((api_secs % 60))
        api_duration_info="   |   $(printf '\033[0;36m')API ${api_mins}m ${api_remaining_secs}s$(printf '\033[0m')"
    elif [ $api_secs -gt 0 ]; then
        api_duration_info="   |   $(printf '\033[0;36m')API ${api_secs}.${api_ms:0:1}s$(printf '\033[0m')"
    else
        api_duration_info="   |   $(printf '\033[0;36m')API ${api_duration_ms}ms$(printf '\033[0m')"
    fi
fi

# Code changes (lines added/removed)
code_changes=""
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
    code_changes="   |   $(printf '\033[0;32m')+${lines_added}$(printf '\033[0m') $(printf '\033[0;31m')-${lines_removed}$(printf '\033[0m')"
fi

# Token counts (input/output)
token_info=""
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

format_tokens() {
    local tokens=$1
    if [ "$tokens" -ge 1000000 ]; then
        echo "$(echo "scale=1; $tokens / 1000000" | bc)M"
    elif [ "$tokens" -ge 1000 ]; then
        echo "$(echo "scale=1; $tokens / 1000" | bc)k"
    else
        echo "$tokens"
    fi
}

if [ "$total_input" -gt 0 ] || [ "$total_output" -gt 0 ]; then
    input_fmt=$(format_tokens $total_input)
    output_fmt=$(format_tokens $total_output)
    token_info="   |   $(printf '\033[0;37m')${input_fmt}/${output_fmt}$(printf '\033[0m')"
fi

# Get session cost (prefer official value, fallback to calculation)
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
if [ "$session_cost" = "0" ] || [ "$session_cost" = "null" ]; then
    # Fallback: calculate from tokens
    if [ "$total_input" -gt 0 ] || [ "$total_output" -gt 0 ]; then
        case "$model_name" in
            *"Opus"*)
                input_price=15.00
                output_price=75.00
                ;;
            *"Sonnet"*)
                input_price=3.00
                output_price=15.00
                ;;
            *"Haiku"*)
                input_price=0.25
                output_price=1.25
                ;;
            *)
                input_price=3.00
                output_price=15.00
                ;;
        esac
        input_cost=$(echo "scale=6; $total_input * $input_price / 1000000" | bc)
        output_cost=$(echo "scale=6; $total_output * $output_price / 1000000" | bc)
        session_cost=$(echo "scale=6; $input_cost + $output_cost" | bc)
    fi
fi

# Format session cost display
session_cost_info=""
if [ -n "$session_cost" ] && [ "$session_cost" != "0" ]; then
    if (( $(echo "$session_cost >= 1" | bc -l) )); then
        session_display=$(printf "%.2f" $session_cost)
    else
        session_display=$(printf "%.3f" $session_cost)
    fi
    session_cost_info="   |   $(printf '\033[0;35m')S:\$${session_display}$(printf '\033[0m')"
fi

# Weekly cost tracking
# Update tracking file with current session
update_weekly_tracking() {
    local cost=$1
    local session=$2
    local now=$(date +%s)
    local week_ago=$((now - 604800))  # 7 days in seconds

    # Initialize tracking file if it doesn't exist
    if [ ! -f "$TRACKING_FILE" ]; then
        echo '{"sessions":[]}' > "$TRACKING_FILE"
    fi

    # Read existing data, filter old entries, update/add current session
    local updated=$(jq --arg session "$session" --argjson cost "$cost" --argjson now "$now" --argjson week_ago "$week_ago" '
        .sessions = [.sessions[] | select(.timestamp > $week_ago and .session_id != $session)] +
        [{"session_id": $session, "cost": $cost, "timestamp": $now}]
    ' "$TRACKING_FILE" 2>/dev/null)

    if [ -n "$updated" ]; then
        echo "$updated" > "$TRACKING_FILE"
    fi
}

# Calculate weekly total
get_weekly_total() {
    local now=$(date +%s)
    local week_ago=$((now - 604800))

    if [ -f "$TRACKING_FILE" ]; then
        jq --argjson week_ago "$week_ago" '[.sessions[] | select(.timestamp > $week_ago) | .cost] | add // 0' "$TRACKING_FILE" 2>/dev/null
    else
        echo "0"
    fi
}

# Update tracking with current session cost
if [ -n "$session_cost" ] && [ "$session_cost" != "0" ] && [ "$SESSION_ID" != "unknown" ]; then
    update_weekly_tracking "$session_cost" "$SESSION_ID" 2>/dev/null
fi

# Get weekly total
weekly_cost=$(get_weekly_total)
weekly_cost_info=""
if [ -n "$weekly_cost" ] && [ "$weekly_cost" != "0" ] && [ "$weekly_cost" != "null" ]; then
    if (( $(echo "$weekly_cost >= 1" | bc -l) )); then
        weekly_display=$(printf "%.2f" $weekly_cost)
    else
        weekly_display=$(printf "%.3f" $weekly_cost)
    fi
    weekly_cost_info="   |   $(printf '\033[0;36m')W:\$${weekly_display}$(printf '\033[0m')"
fi

# Assemble status line with spacing
printf "$(printf '\033[0;34m')%s$(printf '\033[0m')   |   $(printf '\033[0;32m')%s$(printf '\033[0m')%s%s%s%s%s%s%s%s" \
    "$model_short" "$dir_name" "$git_branch" "$context_info" "$duration_info" "$api_duration_info" "$code_changes" "$token_info" "$session_cost_info" "$weekly_cost_info"
