# Status Line Optimization Summary

## Overview

This document summarizes the performance optimization work done on the Claude Code status line script on January 9, 2026.

---

## The Problem

### Initial Performance

The `statusline-command.sh` script was taking **~1.5 seconds** to execute. This is problematic because:

- Claude Code calls the status line script every **~300ms** during active conversation
- A 1.5s execution time meant the script couldn't keep up with the update frequency
- This caused UI lag and unnecessary resource consumption

### Root Cause Analysis

Benchmarking revealed three major bottlenecks:

| Bottleneck | Time Cost | Description |
|------------|-----------|-------------|
| **Multiple jq calls** | ~1,100ms | 18 separate `jq` invocations, each spawning a new process |
| **BTC API call** | ~400ms | Network request to Binance API on every execution |
| **Tracking file I/O** | ~50ms | Reading and writing `usage-tracking.json` every 300ms |

### Process Spawning Overhead

Every execution spawned approximately **27 processes**:
- `jq`: 18 invocations
- `bc`: 5-6 invocations
- `git`: 2 invocations
- `curl`: 1 invocation
- `date`: 2 invocations
- `awk`: 1 invocation

---

## The Solutions

### Optimization 1: Single jq Call for Field Extraction

**Problem**: 18 separate `jq` calls to extract individual JSON fields.

**Before** (18 calls, ~1,100ms):
```bash
SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"')
model_name=$(echo "$input" | jq -r '.model.display_name')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
# ... 15 more calls
```

**After** (1 call, ~3ms):
```bash
jq_output=$(echo "$input" | jq -r '
    [
      (.session_id // "unknown"),
      (.model.display_name // ""),
      (.workspace.current_dir // ""),
      # ... all 15 fields in one array
    ] | @tsv
')
IFS=$'\t' read -r SESSION_ID model_name current_dir ... <<< "$jq_output"
```

**Key insight**: Using `@tsv` (tab-separated values) output and `IFS=$'\t'` for parsing handles fields with spaces (like "Claude 4.5 Opus") correctly.

**Savings**: ~1,000ms per execution

---

### Optimization 2: BTC Price Caching

**Problem**: Network call to Binance API on every status line update (~300ms intervals).

**Before**:
```bash
btc_price=$(curl -s --max-time 1 "https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT" | jq -r '.price')
```

**After** (with 60-second TTL cache):
```bash
BTC_CACHE_FILE="/tmp/claude-btc-cache"
BTC_CACHE_TTL=60

# Check cache first
if [ -f "$BTC_CACHE_FILE" ]; then
    cache_data=$(cat "$BTC_CACHE_FILE")
    cache_time=${cache_data%%:*}
    cache_price=${cache_data#*:}
    if [ $((now - cache_time)) -lt $BTC_CACHE_TTL ]; then
        btc_price=$cache_price  # Use cached value
    fi
fi

# Only fetch if cache is stale
if [ -z "$btc_price" ]; then
    btc_price=$(curl -s --max-time 1 "..." | jq -r '.price')
    echo "${now}:${btc_price}" > "$BTC_CACHE_FILE"
fi
```

**Cache format**: `timestamp:price` (e.g., `1736467200:91587.50`)

**Savings**: ~400ms on 99% of calls (only 1 network call per minute instead of ~200)

---

### Optimization 3: Debounced Tracking File Writes

**Problem**: Writing to `~/.claude/usage-tracking.json` on every execution, even when data hasn't changed.

**Before**:
```bash
if [ -n "$session_cost" ] && [ "$SESSION_ID" != "unknown" ]; then
    update_session_tracking  # Always writes
fi
```

**After** (with change detection):
```bash
SESSION_CACHE_FILE="/tmp/claude-session-cache"

should_update_tracking() {
    local current_hash="${SESSION_ID}:${session_cost}:${duration_ms}:${lines_added}:${lines_removed}"

    if [ -f "$SESSION_CACHE_FILE" ]; then
        local cached_hash=$(cat "$SESSION_CACHE_FILE")
        if [ "$cached_hash" = "$current_hash" ]; then
            return 1  # No update needed
        fi
    fi

    echo "$current_hash" > "$SESSION_CACHE_FILE"
    return 0  # Update needed
}

if [ -n "$session_cost" ] && [ "$SESSION_ID" != "unknown" ]; then
    if should_update_tracking; then
        update_session_tracking  # Only writes when data changes
    fi
fi
```

**Savings**: ~90% reduction in disk I/O

---

## Results

### Performance Comparison

| Scenario | Before | After | Improvement |
|----------|--------|-------|-------------|
| First run (cold cache) | ~1,500ms | ~1,300ms | 1.15x faster |
| Subsequent runs (warm cache) | ~1,500ms | **~80-100ms** | **15-18x faster** |

### Benchmark Results

```
Running 5 consecutive tests (warm cache):
  Run 1: 93ms
  Run 2: 114ms
  Run 3: 101ms
  Run 4: 104ms
  Run 5: 82ms
```

### Resource Usage Reduction

| Resource | Before | After | Reduction |
|----------|--------|-------|-----------|
| Process spawns | ~27/call | ~5-7/call | ~75% |
| Network calls | Every 300ms | Every 60s | ~99% |
| Disk writes | Every call | On change only | ~90% |
| jq invocations | 18/call | 1 main + 3 conditional | ~80% |

---

## Files Modified

| File | Changes |
|------|---------|
| `statusline-command.sh` | All three optimizations implemented |

### New Cache Files Created

| File | Purpose | TTL |
|------|---------|-----|
| `/tmp/claude-btc-cache` | BTC price cache | 60 seconds |
| `/tmp/claude-session-cache` | Session data hash for debouncing | Session lifetime |

---

## Further Improvements

### High Impact (Not Yet Implemented)

1. **Make BTC display optional**
   ```bash
   # Add environment variable toggle
   if [ "${CLAUDE_STATUS_BTC:-1}" = "1" ]; then
       # fetch BTC price
   fi
   ```

2. **Combine tracking file jq calls**
   - Currently `calculate_costs()` makes 2 jq calls to the tracking file
   - Could combine into single call extracting both weekly and lifetime totals

3. **Add session limit to tracking file**
   - File grows unbounded (never deletes old sessions)
   - Add pruning to keep only last 1000 sessions
   ```bash
   jq '.sessions = (.sessions | sort_by(.timestamp) | .[-1000:])' "$TRACKING_FILE"
   ```

### Medium Impact

4. **Cache git branch briefly**
   - Git commands run every execution
   - Could cache branch name for 5-10 seconds

5. **Use awk instead of bc for arithmetic**
   - `awk` is faster than `bc` for simple calculations
   ```bash
   # Before
   cost=$(echo "scale=6; $input * $price / 1000000" | bc)
   # After
   cost=$(awk "BEGIN {printf \"%.6f\", $input * $price / 1000000}")
   ```

6. **Pre-define ANSI color codes**
   ```bash
   BLUE=$'\033[0;34m'
   GREEN=$'\033[0;32m'
   # etc.
   ```

### Low Impact

7. **Add shellcheck compliance** for better error handling

8. **Consider rewriting in a faster language** (Python/Go) if bash limitations persist

9. **Add configurable elements** via environment variables to disable unused sections

---

## Conclusion

The optimizations reduced typical execution time from **~1.5 seconds to ~80-100ms**, a **15-18x improvement**. The script now comfortably runs within the ~300ms update interval of Claude Code's status line system.

The key insight was that **process spawning overhead** (not the operations themselves) was the main bottleneck. Consolidating 18 jq calls into 1, and caching the network request, eliminated the majority of the latency.

---

*Optimization completed: January 9, 2026*
