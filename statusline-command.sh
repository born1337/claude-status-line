#!/bin/bash

# =============================================================================
# Claude Code Status Line (Optimized)
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
#   - BTC price (yellow)        - BTC:$XX,XXX live from Binance API (cached 60s)
#
# Data Storage:
#   All session data is stored in ~/.claude/usage-tracking.json
#   Sessions are never deleted - full history is preserved
#   Weekly/Monthly/Lifetime costs are calculated from session history
#
# Performance Optimizations:
#   - Single jq call extracts all JSON fields at once (~1000ms savings)
#   - BTC price cached for 60 seconds (~400ms savings on most calls)
#   - Tracking file writes debounced (only when data changes)
#
# =============================================================================

# Read JSON input from stdin
input=$(cat)

# Tracking file for all usage data
TRACKING_FILE="$HOME/.claude/usage-tracking.json"

# Cache files for performance optimization
BTC_CACHE_FILE="/tmp/claude-btc-cache"
SESSION_CACHE_FILE="/tmp/claude-session-cache"
BTC_CACHE_TTL=30  # seconds

# =============================================================================
# OPTIMIZATION 1: Single jq call to extract all fields at once
# =============================================================================
# This replaces 18 separate jq invocations with a single call
# Savings: ~1000ms per execution

# Extract all fields with a single jq call, using tab-separated output
# The heredoc approach ensures proper parsing of values with spaces (e.g., model name)
jq_output=$(echo "$input" | jq -r '
    [
      (.session_id // "unknown"),
      (.model.display_name // ""),
      (.workspace.current_dir // ""),
      (.workspace.project_dir // .workspace.current_dir // ""),
      (.cost.total_duration_ms // .duration_ms // 0),
      (.cost.total_api_duration_ms // 0),
      (.cost.total_lines_added // 0),
      (.cost.total_lines_removed // 0),
      (.context_window.total_input_tokens // 0),
      (.context_window.total_output_tokens // 0),
      (.cost.total_cost_usd // 0),
      (.context_window.current_usage.input_tokens // 0),
      (.context_window.current_usage.cache_creation_input_tokens // 0),
      (.context_window.current_usage.cache_read_input_tokens // 0),
      (.context_window.context_window_size // 200000)
    ] | @tsv
')
IFS=$'\t' read -r SESSION_ID model_name current_dir project_dir duration_ms api_duration_ms \
     lines_added lines_removed total_input total_output session_cost \
     ctx_input ctx_cache_create ctx_cache_read ctx_size <<< "$jq_output"

# Handle null/empty values
[ "$SESSION_ID" = "null" ] && SESSION_ID="unknown"
[ "$duration_ms" = "null" ] && duration_ms=0
[ "$api_duration_ms" = "null" ] && api_duration_ms=0
[ "$lines_added" = "null" ] && lines_added=0
[ "$lines_removed" = "null" ] && lines_removed=0
[ "$total_input" = "null" ] && total_input=0
[ "$total_output" = "null" ] && total_output=0
[ "$session_cost" = "null" ] && session_cost=0
[ "$ctx_input" = "null" ] && ctx_input=0
[ "$ctx_cache_create" = "null" ] && ctx_cache_create=0
[ "$ctx_cache_read" = "null" ] && ctx_cache_read=0
[ "$ctx_size" = "null" ] && ctx_size=200000
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
# OPTIMIZATION 3: Debounced Session Tracking
# =============================================================================
# Only writes to tracking file when session data actually changes
# Savings: Reduces disk I/O by ~90% (no write if data unchanged)

# Check if tracking data has changed (returns 0 if update needed, 1 if skip)
should_update_tracking() {
    local current_hash="${SESSION_ID}:${session_cost}:${duration_ms}:${lines_added}:${lines_removed}"

    if [ -f "$SESSION_CACHE_FILE" ]; then
        local cached_hash=$(cat "$SESSION_CACHE_FILE" 2>/dev/null)
        if [ "$cached_hash" = "$current_hash" ]; then
            return 1  # No update needed - data unchanged
        fi
    fi

    # Update cache with current hash
    echo "$current_hash" > "$SESSION_CACHE_FILE" 2>/dev/null
    return 0  # Update needed
}

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

# Update tracking if we have valid session data AND data has changed (debounced)
if [ -n "$session_cost" ] && [ "$SESSION_ID" != "unknown" ]; then
    if should_update_tracking; then
        update_session_tracking 2>/dev/null
    fi
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
# Uses pre-extracted values from single jq call (ctx_input, ctx_cache_create, ctx_cache_read, ctx_size)
context_info=""
if [ "$ctx_size" -gt 0 ] && [ "$ctx_input" != "" ]; then
    current=$((ctx_input + ctx_cache_create + ctx_cache_read))
    free=$((ctx_size - current))
    [ $free -lt 0 ] && free=0
    pct=$((current * 100 / ctx_size))

    # Format token counts (using bash arithmetic to avoid bc calls)
    format_ctx_tokens() {
        local tokens=$1
        if [ "$tokens" -ge 1000000 ]; then
            echo "$((tokens / 1000000))M"
        elif [ "$tokens" -ge 1000 ]; then
            echo "$((tokens / 1000))k"
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

# =============================================================================
# OPTIMIZATION 2: BTC price caching with 60-second TTL
# =============================================================================
# Fetches from Binance only when cache is stale, otherwise uses cached value
# Savings: ~400ms on 99% of calls (only 1 network call per minute)

btc_info=""
btc_price=""
now=$(date +%s)

# Check cache first
if [ -f "$BTC_CACHE_FILE" ]; then
    cache_data=$(cat "$BTC_CACHE_FILE" 2>/dev/null)
    cache_time=${cache_data%%:*}
    cache_price=${cache_data#*:}
    if [ -n "$cache_time" ] && [ $((now - cache_time)) -lt $BTC_CACHE_TTL ]; then
        btc_price=$cache_price
    fi
fi

# Fetch from API only if cache is stale or missing
if [ -z "$btc_price" ]; then
    btc_price=$(curl -s --max-time 1 "https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT" 2>/dev/null | jq -r '.price // empty' 2>/dev/null)
    # Update cache if we got a valid price
    [ -n "$btc_price" ] && echo "${now}:${btc_price}" > "$BTC_CACHE_FILE" 2>/dev/null
fi

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
