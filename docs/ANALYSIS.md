# Project Analysis: Claude Code Status Line

## What This Project Does

This is a **custom status line for Claude Code CLI** that displays real-time metrics at the bottom of your terminal. It shows:

| Element | Description |
|---------|-------------|
| Model name | Current AI model (Opus/Sonnet/Haiku) |
| Directory | Current working folder |
| Git branch | Active branch name |
| Context window | Token usage with color coding |
| Session duration | Time in current session |
| API duration | Time spent in API calls |
| Code changes | Lines added/removed |
| Session cost | Current session $ |
| Weekly cost | Rolling 7-day total |
| Lifetime cost | All-time total |
| BTC price | Live Bitcoin price from Binance |

### How It Works

1. Claude Code calls `statusline-command.sh` every ~300ms during conversation activity
2. The script receives JSON data via stdin with session metrics
3. Parses the JSON, calculates costs, fetches BTC price
4. Persists session data to `~/.claude/usage-tracking.json`
5. Outputs formatted ANSI-colored text

---

## Performance Analysis

### Current Execution Time: ~1.5 seconds

This is **far too slow** for a status line that updates every 300ms.

| Component | Time | Issue |
|-----------|------|-------|
| BTC API call (curl) | ~400ms | Network latency (1s timeout) |
| 18× jq invocations | ~1100ms | Process spawning overhead |
| bc arithmetic | ~20ms | 5-6 process spawns |
| git commands | ~10ms | 2 process spawns |
| File I/O | ~5ms | Read/write tracking file |

### Process Spawn Analysis

Every execution spawns approximately **27 processes**:
- `jq`: 18 invocations
- `bc`: 5-6 invocations
- `git`: 2 invocations
- `curl`: 1 invocation
- `date`: 2 invocations
- `awk`: 1 invocation

---

## Critical Issues & Optimizations

### 🔴 CRITICAL: BTC API Call on Every Update

**Location**: `statusline-command.sh:295`

```bash
btc_price=$(curl -s --max-time 1 "https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT" ...)
```

**Problem**: Network call every ~300ms is:
- Wasteful (BTC price doesn't change that fast)
- Adds 400ms+ latency per execution
- Could timeout/fail and slow things down further
- Unnecessary API load on Binance

**Solution**: Cache BTC price with TTL

```bash
BTC_CACHE_FILE="/tmp/btc-price-cache"
BTC_CACHE_TTL=60  # seconds

get_btc_price() {
    local now=$(date +%s)
    if [ -f "$BTC_CACHE_FILE" ]; then
        local cached=$(cat "$BTC_CACHE_FILE")
        local cache_time=$(echo "$cached" | cut -d: -f1)
        local cache_price=$(echo "$cached" | cut -d: -f2)
        if [ $((now - cache_time)) -lt $BTC_CACHE_TTL ]; then
            echo "$cache_price"
            return
        fi
    fi
    local price=$(curl -s --max-time 1 "https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT" | jq -r '.price // empty')
    [ -n "$price" ] && echo "$now:$price" > "$BTC_CACHE_FILE"
    echo "$price"
}
```

**Expected savings**: ~400ms on most executions (99% of calls)

---

### 🔴 CRITICAL: Multiple jq Invocations

**Location**: `statusline-command.sh:37-51, 183-186`

**Problem**: 18 separate `jq` calls, each spawning a new process. Benchmarks showed:
- 18× jq calls: **~1100ms**
- 1× jq call extracting all fields: **~3ms**

**Solution**: Single jq call to extract all values at once

```bash
# Before: 18 separate calls
SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"')
model_name=$(echo "$input" | jq -r '.model.display_name')
# ... 16 more calls

# After: Single call with multiple outputs
read -r SESSION_ID model_name current_dir project_dir duration_ms api_duration_ms \
     lines_added lines_removed total_input total_output session_cost \
     ctx_input ctx_cache_create ctx_cache_read ctx_size <<< $(echo "$input" | jq -r '
     [
       .session_id // "unknown",
       .model.display_name // "",
       .workspace.current_dir // "",
       .workspace.project_dir // .workspace.current_dir // "",
       .cost.total_duration_ms // .duration_ms // 0,
       .cost.total_api_duration_ms // 0,
       .cost.total_lines_added // 0,
       .cost.total_lines_removed // 0,
       .context_window.total_input_tokens // 0,
       .context_window.total_output_tokens // 0,
       .cost.total_cost_usd // 0,
       .context_window.current_usage.input_tokens // 0,
       .context_window.current_usage.cache_creation_input_tokens // 0,
       .context_window.current_usage.cache_read_input_tokens // 0,
       .context_window.context_window_size // 200000
     ] | @tsv
')
```

**Expected savings**: ~1000ms per execution

---

### 🟠 MODERATE: Unbounded Tracking File Growth

**Location**: `statusline-command.sh:82-125`

**Problem**: Sessions are never deleted. The file currently has 18 sessions (238 lines). Over time:
- File grows indefinitely
- `jq` must parse entire history each time
- Cost aggregation queries slow down

**Current**: 6.8KB, 18 sessions
**After 1 year of heavy use**: Could be 500KB+ with 1000+ sessions

**Solution Options**:

1. **Archive old sessions** - Move sessions older than 90 days to archive file
2. **Limit session count** - Keep only last N sessions, archive the rest
3. **Periodic cleanup** - Cron job to prune old data

```bash
# Option: Keep only last 1000 sessions
prune_old_sessions() {
    jq '.sessions = (.sessions | sort_by(.timestamp) | .[-1000:])' "$TRACKING_FILE" > "$TRACKING_FILE.tmp"
    mv "$TRACKING_FILE.tmp" "$TRACKING_FILE"
}
```

---

### 🟠 MODERATE: Tracking File I/O Every Update

**Problem**: The script reads and writes `usage-tracking.json` on every execution (~300ms intervals).

**Solution**: Debounce writes - only update tracking file if session_id or cost changed

```bash
LAST_SESSION_CACHE="/tmp/claude-last-session"

should_update_tracking() {
    local last=""
    [ -f "$LAST_SESSION_CACHE" ] && last=$(cat "$LAST_SESSION_CACHE")
    local current="${SESSION_ID}:${session_cost}"
    if [ "$last" = "$current" ]; then
        return 1  # No update needed
    fi
    echo "$current" > "$LAST_SESSION_CACHE"
    return 0
}
```

---

### 🟡 MINOR: bc for Simple Arithmetic

**Problem**: Using `bc` for calculations that bash can do natively.

```bash
# Current (spawns bc):
input_cost=$(echo "scale=6; $total_input * $input_price / 1000000" | bc)

# Better (bash arithmetic where possible):
total_secs=$((duration_ms / 1000))  # Already using this correctly
```

For floating-point operations, `awk` is faster than `bc`:
```bash
# Using awk instead of bc:
input_cost=$(awk "BEGIN {printf \"%.6f\", $total_input * $input_price / 1000000}")
```

---

### 🟡 MINOR: Color Code Efficiency

**Problem**: Multiple `printf '\033[0;34m'` calls throughout.

**Solution**: Define color variables once at the top:

```bash
BLUE=$'\033[0;34m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'
MAGENTA=$'\033[0;35m'
WHITE=$'\033[0;37m'
RESET=$'\033[0m'
```

---

## Resource Usage Summary

| Resource | Current Impact | Optimized Impact |
|----------|----------------|------------------|
| **Execution time** | ~1.5s | ~50-100ms |
| **Process spawns** | ~27 per call | ~5-7 per call |
| **Network calls** | Every 300ms | Every 60s |
| **Disk I/O** | Read+write every call | Write only on change |
| **Memory** | Minimal | Minimal |
| **CPU** | High (process spawning) | Low |

---

## Recommended Optimizations (Prioritized)

### High Priority (Biggest Impact)

1. **Cache BTC price** with 60-second TTL → Saves ~400ms on 99% of calls
2. **Single jq call** for all field extraction → Saves ~1000ms per call
3. **Debounce tracking file writes** → Reduces disk I/O by ~90%

### Medium Priority

4. **Add session limit** to tracking file (e.g., keep last 1000)
5. **Consider making BTC optional** via environment variable

### Low Priority

6. Use `awk` instead of `bc` where possible
7. Pre-define ANSI color codes as variables
8. Cache git branch name briefly

---

## Additional Suggestions

### Feature Ideas

1. **Configurable elements** - Environment variables to enable/disable sections
2. **Multiple crypto support** - Not just BTC, configurable
3. **Cost alerts** - Color change when approaching budget limits
4. **Project-specific tracking** - Group costs by project directory

### Code Quality

1. Add `set -euo pipefail` for better error handling
2. Add shellcheck compliance
3. Consider rewriting in a faster language (Python/Go) if bash limitations persist

---

## Quick Win Implementation

Here's the BTC caching fix you can apply immediately to save ~400ms on most calls:

```bash
# Replace lines 293-301 with:
btc_info=""
BTC_CACHE="/tmp/btc-price-cache"
now=$(date +%s)
if [ -f "$BTC_CACHE" ]; then
    cache_data=$(cat "$BTC_CACHE")
    cache_time=${cache_data%%:*}
    cache_price=${cache_data#*:}
    if [ $((now - cache_time)) -lt 60 ]; then
        btc_price=$cache_price
    fi
fi
if [ -z "${btc_price:-}" ]; then
    btc_price=$(curl -s --max-time 1 "https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT" 2>/dev/null | jq -r '.price // empty' 2>/dev/null)
    [ -n "$btc_price" ] && echo "${now}:${btc_price}" > "$BTC_CACHE"
fi
if [ -n "$btc_price" ]; then
    btc_int=$(printf "%.0f" "$btc_price")
    btc_formatted=$(echo "$btc_int" | awk '{ printf "%\047d\n", $1 }' 2>/dev/null || echo "$btc_int")
    btc_info="   |   $(printf '\033[0;33m')BTC:\$${btc_formatted}$(printf '\033[0m')"
fi
```

---

## Benchmark Results

```
# Current implementation
$ time ./statusline-command.sh
real    1.474s

# Single jq call (all extractions)
$ time jq '{...all fields...}'
real    0.003s

# Potential optimized total
Estimated: 50-100ms
```

---

*Analysis generated: January 2026*
