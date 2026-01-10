#!/bin/bash

# =============================================================================
# Claude Code Status Line (Configurable)
# =============================================================================
#
# Display format:
#   Opus 4.5   |   test   |   [main]   |   22k/178k   |   2m 30s   |   API 2.3s   |   +156 -23   |   S:$0.42   |   W:$12.50   |   L:$150.25   |   BTC:$90,310
#
# Configuration:
#   Edit ~/.claude/statusline.conf or use: statusline-config --help
#   All elements can be enabled/disabled and colors customized.
#
# Performance Optimizations:
#   - Single jq call extracts all JSON fields at once (~1000ms savings)
#   - BTC price cached (configurable TTL, default 30s)
#   - Tracking file writes debounced (only when data changes)
#   - Config sourced directly (no JSON parsing overhead)
#
# =============================================================================

# Read JSON input from stdin
input=$(cat)

# =============================================================================
# Configuration Loading
# =============================================================================

CONFIG_FILE="$HOME/.claude/statusline.conf"
TRACKING_FILE="$HOME/.claude/usage-tracking.json"

# Default values (used if config file doesn't exist or variable is missing)
SHOW_MODEL=${SHOW_MODEL:-1}
SHOW_DIRECTORY=${SHOW_DIRECTORY:-1}
SHOW_GIT_BRANCH=${SHOW_GIT_BRANCH:-1}
SHOW_CONTEXT=${SHOW_CONTEXT:-1}
SHOW_DURATION=${SHOW_DURATION:-1}
SHOW_API_DURATION=${SHOW_API_DURATION:-1}
SHOW_CODE_CHANGES=${SHOW_CODE_CHANGES:-1}
SHOW_SESSION_COST=${SHOW_SESSION_COST:-1}
SHOW_WEEKLY_COST=${SHOW_WEEKLY_COST:-1}
SHOW_LIFETIME_COST=${SHOW_LIFETIME_COST:-1}
SHOW_BTC=${SHOW_BTC:-1}

COLOR_MODEL=${COLOR_MODEL:-blue}
COLOR_DIRECTORY=${COLOR_DIRECTORY:-green}
COLOR_GIT_BRANCH=${COLOR_GIT_BRANCH:-cyan}
COLOR_DURATION=${COLOR_DURATION:-yellow}
COLOR_API_DURATION=${COLOR_API_DURATION:-cyan}
COLOR_SESSION_COST=${COLOR_SESSION_COST:-magenta}
COLOR_WEEKLY_COST=${COLOR_WEEKLY_COST:-cyan}
COLOR_LIFETIME_COST=${COLOR_LIFETIME_COST:-white}
COLOR_BTC=${COLOR_BTC:-yellow}
COLOR_CONTEXT_LOW=${COLOR_CONTEXT_LOW:-green}
COLOR_CONTEXT_MED=${COLOR_CONTEXT_MED:-yellow}
COLOR_CONTEXT_HIGH=${COLOR_CONTEXT_HIGH:-red}
COLOR_ADDED=${COLOR_ADDED:-green}
COLOR_REMOVED=${COLOR_REMOVED:-red}

BTC_CACHE_TTL=${BTC_CACHE_TTL:-30}
SEPARATOR=${SEPARATOR:-"   |   "}

# Load config file if it exists (overrides defaults)
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# Cache files for performance optimization
BTC_CACHE_FILE="/tmp/claude-btc-cache"
SESSION_CACHE_FILE="/tmp/claude-session-cache"

# =============================================================================
# Color Mapping
# =============================================================================

get_color_code() {
    local color_name="$1"
    case "$color_name" in
        black)          echo '\033[0;30m' ;;
        red)            echo '\033[0;31m' ;;
        green)          echo '\033[0;32m' ;;
        yellow)         echo '\033[0;33m' ;;
        blue)           echo '\033[0;34m' ;;
        magenta)        echo '\033[0;35m' ;;
        cyan)           echo '\033[0;36m' ;;
        white)          echo '\033[0;37m' ;;
        bright_black)   echo '\033[1;30m' ;;
        bright_red)     echo '\033[1;31m' ;;
        bright_green)   echo '\033[1;32m' ;;
        bright_yellow)  echo '\033[1;33m' ;;
        bright_blue)    echo '\033[1;34m' ;;
        bright_magenta) echo '\033[1;35m' ;;
        bright_cyan)    echo '\033[1;36m' ;;
        bright_white)   echo '\033[1;37m' ;;
        *)              echo '\033[0;37m' ;;  # Default to white
    esac
}

RESET='\033[0m'

# =============================================================================
# Data Extraction (Single jq call for performance)
# =============================================================================

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

# Calculate session cost if not provided
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
# Session Tracking (Debounced)
# =============================================================================

should_update_tracking() {
    local current_hash="${SESSION_ID}:${session_cost}:${duration_ms}:${lines_added}:${lines_removed}"
    if [ -f "$SESSION_CACHE_FILE" ]; then
        local cached_hash=$(cat "$SESSION_CACHE_FILE" 2>/dev/null)
        if [ "$cached_hash" = "$current_hash" ]; then
            return 1
        fi
    fi
    echo "$current_hash" > "$SESSION_CACHE_FILE" 2>/dev/null
    return 0
}

update_session_tracking() {
    local now=$(date +%s)
    if [ ! -f "$TRACKING_FILE" ]; then
        echo '{"sessions":[]}' > "$TRACKING_FILE"
    fi
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
        .sessions = [.sessions[] | select(.session_id != $session_id)] +
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
    [ -n "$updated" ] && echo "$updated" > "$TRACKING_FILE"
}

calculate_costs() {
    local now=$(date +%s)
    local week_ago=$((now - 604800))
    if [ -f "$TRACKING_FILE" ]; then
        weekly=$(jq --argjson week_ago "$week_ago" --arg current "$SESSION_ID" \
            '[.sessions[] | select(.timestamp > $week_ago and .session_id != $current) | .cost] | add // 0' \
            "$TRACKING_FILE" 2>/dev/null)
        lifetime=$(jq --arg current "$SESSION_ID" \
            '[.sessions[] | select(.session_id != $current) | .cost] | add // 0' \
            "$TRACKING_FILE" 2>/dev/null)
        echo "$weekly $lifetime"
    else
        echo "0 0"
    fi
}

# Update tracking if needed
if [ -n "$session_cost" ] && [ "$SESSION_ID" != "unknown" ]; then
    if should_update_tracking; then
        update_session_tracking 2>/dev/null
    fi
fi

# Get calculated costs
read weekly_total lifetime_total <<< $(calculate_costs 2>/dev/null)
weekly_cost=$(echo "scale=6; ${weekly_total:-0} + ${session_cost:-0}" | bc)
lifetime_cost=$(echo "scale=6; ${lifetime_total:-0} + ${session_cost:-0}" | bc)

# =============================================================================
# Format Helper Functions
# =============================================================================

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

format_tokens() {
    local tokens=$1
    if [ "$tokens" -ge 1000000 ]; then
        echo "$((tokens / 1000000))M"
    elif [ "$tokens" -ge 1000 ]; then
        echo "$((tokens / 1000))k"
    else
        echo "$tokens"
    fi
}

# =============================================================================
# Build Status Line Elements
# =============================================================================

output=""

# Model name
if [ "$SHOW_MODEL" = "1" ]; then
    model_short=$(echo "$model_name" | sed -E 's/Claude ([0-9.]+) (Opus|Sonnet|Haiku)/\2 \1/')
    color=$(get_color_code "$COLOR_MODEL")
    output+="$(printf "${color}")${model_short}$(printf "${RESET}")"
fi

# Directory
if [ "$SHOW_DIRECTORY" = "1" ]; then
    dir_name=$(basename "$current_dir")
    color=$(get_color_code "$COLOR_DIRECTORY")
    [ -n "$output" ] && output+="$SEPARATOR"
    output+="$(printf "${color}")${dir_name}$(printf "${RESET}")"
fi

# Git branch
if [ "$SHOW_GIT_BRANCH" = "1" ]; then
    if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
        branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
        if [ -n "$branch" ]; then
            color=$(get_color_code "$COLOR_GIT_BRANCH")
            [ -n "$output" ] && output+="$SEPARATOR"
            output+="$(printf "${color}")[${branch}]$(printf "${RESET}")"
        fi
    fi
fi

# Context window
if [ "$SHOW_CONTEXT" = "1" ] && [ "$ctx_size" -gt 0 ] && [ -n "$ctx_input" ]; then
    current=$((ctx_input + ctx_cache_create + ctx_cache_read))
    free=$((ctx_size - current))
    [ $free -lt 0 ] && free=0
    pct=$((current * 100 / ctx_size))

    used_fmt=$(format_tokens $current)
    max_fmt=$(format_tokens $ctx_size)

    if [ $pct -lt 50 ]; then
        color=$(get_color_code "$COLOR_CONTEXT_LOW")
    elif [ $pct -lt 75 ]; then
        color=$(get_color_code "$COLOR_CONTEXT_MED")
    else
        color=$(get_color_code "$COLOR_CONTEXT_HIGH")
    fi
    [ -n "$output" ] && output+="$SEPARATOR"
    output+="$(printf "${color}")${used_fmt}/${max_fmt} (${pct}%)$(printf "${RESET}")"
fi

# Session duration
if [ "$SHOW_DURATION" = "1" ] && [ "$duration_ms" != "null" ] && [ "$duration_ms" -gt 0 ]; then
    total_secs=$((duration_ms / 1000))
    hours=$((total_secs / 3600))
    mins=$(( (total_secs % 3600) / 60 ))
    secs=$((total_secs % 60))

    color=$(get_color_code "$COLOR_DURATION")
    [ -n "$output" ] && output+="$SEPARATOR"

    if [ $hours -gt 0 ]; then
        output+="$(printf "${color}")${hours}h ${mins}m$(printf "${RESET}")"
    elif [ $mins -gt 0 ]; then
        output+="$(printf "${color}")${mins}m ${secs}s$(printf "${RESET}")"
    else
        output+="$(printf "${color}")${secs}s$(printf "${RESET}")"
    fi
fi

# API duration
if [ "$SHOW_API_DURATION" = "1" ] && [ "$api_duration_ms" != "null" ] && [ "$api_duration_ms" -gt 0 ]; then
    api_secs=$((api_duration_ms / 1000))
    api_ms=$((api_duration_ms % 1000))

    color=$(get_color_code "$COLOR_API_DURATION")
    [ -n "$output" ] && output+="$SEPARATOR"

    if [ $api_secs -ge 60 ]; then
        api_mins=$((api_secs / 60))
        api_remaining_secs=$((api_secs % 60))
        output+="$(printf "${color}")API ${api_mins}m ${api_remaining_secs}s$(printf "${RESET}")"
    elif [ $api_secs -gt 0 ]; then
        output+="$(printf "${color}")API ${api_secs}.${api_ms:0:1}s$(printf "${RESET}")"
    else
        output+="$(printf "${color}")API ${api_duration_ms}ms$(printf "${RESET}")"
    fi
fi

# Code changes
if [ "$SHOW_CODE_CHANGES" = "1" ] && ([ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]); then
    color_add=$(get_color_code "$COLOR_ADDED")
    color_rem=$(get_color_code "$COLOR_REMOVED")
    [ -n "$output" ] && output+="$SEPARATOR"
    output+="$(printf "${color_add}")+${lines_added}$(printf "${RESET}") $(printf "${color_rem}")-${lines_removed}$(printf "${RESET}")"
fi

# Session cost
if [ "$SHOW_SESSION_COST" = "1" ] && [ -n "$session_cost" ] && [ "$session_cost" != "0" ]; then
    session_display=$(format_cost $session_cost)
    color=$(get_color_code "$COLOR_SESSION_COST")
    [ -n "$output" ] && output+="$SEPARATOR"
    output+="$(printf "${color}")S:\$${session_display}$(printf "${RESET}")"
fi

# Weekly cost
if [ "$SHOW_WEEKLY_COST" = "1" ] && [ -n "$weekly_cost" ] && [ "$weekly_cost" != "0" ]; then
    weekly_display=$(format_cost $weekly_cost)
    color=$(get_color_code "$COLOR_WEEKLY_COST")
    [ -n "$output" ] && output+="$SEPARATOR"
    output+="$(printf "${color}")W:\$${weekly_display}$(printf "${RESET}")"
fi

# Lifetime cost
if [ "$SHOW_LIFETIME_COST" = "1" ] && [ -n "$lifetime_cost" ] && [ "$lifetime_cost" != "0" ]; then
    lifetime_display=$(format_cost $lifetime_cost)
    color=$(get_color_code "$COLOR_LIFETIME_COST")
    [ -n "$output" ] && output+="$SEPARATOR"
    output+="$(printf "${color}")L:\$${lifetime_display}$(printf "${RESET}")"
fi

# BTC price (with caching)
if [ "$SHOW_BTC" = "1" ]; then
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

    # Fetch from API only if cache is stale
    if [ -z "$btc_price" ]; then
        btc_price=$(curl -s --max-time 1 "https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT" 2>/dev/null | jq -r '.price // empty' 2>/dev/null)
        [ -n "$btc_price" ] && echo "${now}:${btc_price}" > "$BTC_CACHE_FILE" 2>/dev/null
    fi

    if [ -n "$btc_price" ]; then
        btc_int=$(printf "%.0f" "$btc_price")
        btc_formatted=$(echo "$btc_int" | awk '{ printf "%\047d\n", $1 }' 2>/dev/null || echo "$btc_int")
        color=$(get_color_code "$COLOR_BTC")
        [ -n "$output" ] && output+="$SEPARATOR"
        output+="$(printf "${color}")BTC:\$${btc_formatted}$(printf "${RESET}")"
    fi
fi

# =============================================================================
# Output
# =============================================================================

printf "%s" "$output"
