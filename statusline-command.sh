#!/bin/bash

# =============================================================================
# Claude Code Status Line
# =============================================================================
#
# Display format:
#   Opus 4.5   |   test   |   [main]   |   22k/178k   |   2m 30s   |   API 2.3s   |   +156 -23   |   S:$0.42   |   W:$12.50   |   L:$150.25   |   BTC:$90,310
#
# Elements:
#   - Model name (blue)         - e.g., "Opus 4.5"
#   - Current directory (green) - folder name
#   - Git branch (cyan)         - shows [branch] when in a repo
#   - Context window (color-coded) - used/free tokens (green <50%, yellow 50-75%, red >75%)
#   - Session duration (yellow) - time spent in session
#   - API duration (cyan)       - time spent in API calls
#   - Code changes (green/red)  - lines added/removed
#   - Session cost (magenta)    - S:$X.XX current session cost
#   - Weekly cost (cyan)        - W:$X.XX rolling 7-day total
#   - Lifetime cost (white)     - L:$X.XX all-time total
#   - BTC price (yellow)        - BTC:$XX,XXX live from Binance API
#
# Data Storage:
#   All session data is stored in ~/.claude/usage-tracking.json
#   Sessions are never deleted - full history is preserved
#   Weekly/Monthly/Lifetime costs are calculated from session history
#
# =============================================================================

# Read JSON input from stdin
input=$(cat)

# Tracking file for all usage data
TRACKING_FILE="$HOME/.claude/usage-tracking.json"

# Extract session info
SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"')
model_name=$(echo "$input" | jq -r '.model.display_name')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir')

# Extract metrics
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // .duration_ms // 0')
api_duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Get session cost (prefer official value, fallback to calculation)
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
if [ "$session_cost" = "0" ] || [ "$session_cost" = "null" ]; then
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

# =============================================================================
# Session Tracking - Store comprehensive data for each session
# =============================================================================

update_session_tracking() {
    local now=$(date +%s)

    # Initialize tracking file if it doesn't exist
    if [ ! -f "$TRACKING_FILE" ]; then
        echo '{"sessions":[]}' > "$TRACKING_FILE"
    fi

    # Build session data object and update/insert
    local updated=$(jq \
        --arg session_id "$SESSION_ID" \
        --arg model "$model_name" \
        --arg project_dir "$project_dir" \
        --argjson timestamp "$now" \
        --argjson cost "${session_cost:-0}" \
        --argjson duration_ms "${duration_ms:-0}" \
        --argjson api_duration_ms "${api_duration_ms:-0}" \
        --argjson input_tokens "${total_input:-0}" \
        --argjson output_tokens "${total_output:-0}" \
        --argjson lines_added "${lines_added:-0}" \
        --argjson lines_removed "${lines_removed:-0}" \
        '
        # Remove existing entry for this session (if any)
        .sessions = [.sessions[] | select(.session_id != $session_id)] +
        # Add updated session data
        [{
            "session_id": $session_id,
            "timestamp": $timestamp,
            "model": $model,
            "project_dir": $project_dir,
            "cost": $cost,
            "duration_ms": $duration_ms,
            "api_duration_ms": $api_duration_ms,
            "input_tokens": $input_tokens,
            "output_tokens": $output_tokens,
            "lines_added": $lines_added,
            "lines_removed": $lines_removed
        }]
        ' "$TRACKING_FILE" 2>/dev/null)

    if [ -n "$updated" ]; then
        echo "$updated" > "$TRACKING_FILE"
    fi
}

# Calculate costs from session history
calculate_costs() {
    local now=$(date +%s)
    local week_ago=$((now - 604800))    # 7 days
    local month_ago=$((now - 2592000))  # 30 days

    if [ -f "$TRACKING_FILE" ]; then
        # Get weekly total (excluding current session, we'll add it separately)
        weekly=$(jq --argjson week_ago "$week_ago" --arg current "$SESSION_ID" \
            '[.sessions[] | select(.timestamp > $week_ago and .session_id != $current) | .cost] | add // 0' \
            "$TRACKING_FILE" 2>/dev/null)

        # Get lifetime total (excluding current session)
        lifetime=$(jq --arg current "$SESSION_ID" \
            '[.sessions[] | select(.session_id != $current) | .cost] | add // 0' \
            "$TRACKING_FILE" 2>/dev/null)

        echo "$weekly $lifetime"
    else
        echo "0 0"
    fi
}

# Update tracking if we have valid session data
if [ -n "$session_cost" ] && [ "$SESSION_ID" != "unknown" ]; then
    update_session_tracking 2>/dev/null
fi

# Get calculated costs
read weekly_total lifetime_total <<< $(calculate_costs 2>/dev/null)

# Add current session cost to totals
weekly_cost=$(echo "scale=6; ${weekly_total:-0} + ${session_cost:-0}" | bc)
lifetime_cost=$(echo "scale=6; ${lifetime_total:-0} + ${session_cost:-0}" | bc)

# =============================================================================
# Display Formatting
# =============================================================================

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

# Format session duration
duration_info=""
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

# Format API duration
api_duration_info=""
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

# Format code changes
code_changes=""
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
    code_changes="   |   $(printf '\033[0;32m')+${lines_added}$(printf '\033[0m') $(printf '\033[0;31m')-${lines_removed}$(printf '\033[0m')"
fi

# Format cost helper
format_cost() {
    local cost=$1
    if [ -z "$cost" ] || [ "$cost" = "0" ]; then
        echo "0"
    elif (( $(echo "$cost >= 100" | bc -l) )); then
        printf "%.0f" $cost
    elif (( $(echo "$cost >= 10" | bc -l) )); then
        printf "%.1f" $cost
    elif (( $(echo "$cost >= 1" | bc -l) )); then
        printf "%.2f" $cost
    else
        printf "%.3f" $cost
    fi
}

# Format session cost
session_cost_info=""
if [ -n "$session_cost" ] && [ "$session_cost" != "0" ]; then
    session_display=$(format_cost $session_cost)
    session_cost_info="   |   $(printf '\033[0;35m')S:\$${session_display}$(printf '\033[0m')"
fi

# Format weekly cost
weekly_cost_info=""
if [ -n "$weekly_cost" ] && [ "$weekly_cost" != "0" ]; then
    weekly_display=$(format_cost $weekly_cost)
    weekly_cost_info="   |   $(printf '\033[0;36m')W:\$${weekly_display}$(printf '\033[0m')"
fi

# Format lifetime cost
lifetime_cost_info=""
if [ -n "$lifetime_cost" ] && [ "$lifetime_cost" != "0" ]; then
    lifetime_display=$(format_cost $lifetime_cost)
    lifetime_cost_info="   |   $(printf '\033[0;37m')L:\$${lifetime_display}$(printf '\033[0m')"
fi

# Fetch BTC price from Binance (with timeout to avoid slowdowns)
btc_info=""
btc_price=$(curl -s --max-time 1 "https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT" 2>/dev/null | jq -r '.price // empty' 2>/dev/null)
if [ -n "$btc_price" ]; then
    # Format price with comma separator (cross-platform)
    btc_int=$(printf "%.0f" "$btc_price")
    btc_formatted=$(echo "$btc_int" | awk '{ printf "%\047d\n", $1 }' 2>/dev/null || echo "$btc_int")
    btc_info="   |   $(printf '\033[0;33m')BTC:\$${btc_formatted}$(printf '\033[0m')"
fi

# =============================================================================
# Assemble and output status line
# =============================================================================

printf "$(printf '\033[0;34m')%s$(printf '\033[0m')   |   $(printf '\033[0;32m')%s$(printf '\033[0m')%s%s%s%s%s%s%s%s%s" \
    "$model_short" "$dir_name" "$git_branch" "$context_info" "$duration_info" "$api_duration_info" "$code_changes" "$session_cost_info" "$weekly_cost_info" "$lifetime_cost_info" "$btc_info"
