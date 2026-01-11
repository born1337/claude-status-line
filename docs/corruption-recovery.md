# Tracking File Corruption Recovery

## Problem

The status line tracks session costs in `~/.claude/usage-tracking.json`. Previously, if Claude Code crashed or was interrupted during a write operation, the tracking file could become corrupted (truncated JSON), causing:

- All cost calculations to fail silently (jq returns errors)
- Weekly and lifetime costs displaying as $0
- Loss of historical session data

### Root Cause

The original code used a direct write pattern:
```bash
echo "$updated" > "$TRACKING_FILE"
```

This truncates the file immediately before writing. If interrupted mid-write, you get incomplete JSON like:
```json
{
  "sessions": [
    {
      "session_id": "abc-123",
      "cost": 0.55,
      "timestamp": 1768049493,
```

## Solution

Three layers of protection were added:

### 1. Atomic Writes

Instead of writing directly to the tracking file, the script now:
1. Writes to a temporary file (`usage-tracking.json.tmp.$$`)
2. Validates the JSON is complete using `jq -e`
3. Only then uses `mv` to atomically replace the original

```bash
local tmp_file="${TRACKING_FILE}.tmp.$$"
echo "$updated" > "$tmp_file"
if jq -e '.' "$tmp_file" > /dev/null 2>&1; then
    mv "$tmp_file" "$TRACKING_FILE"
else
    rm -f "$tmp_file"  # Discard invalid data
fi
```

The `mv` operation is atomic on POSIX filesystems - it either completes fully or not at all.

### 2. Automatic Backup

Before each successful write, the current valid file is backed up:
```bash
[ -f "$TRACKING_FILE" ] && cp "$TRACKING_FILE" "$backup_file"
```

This creates `~/.claude/usage-tracking.json.bak` with the last known good state.

### 3. Auto-Recovery

On each script run, before any tracking operations:
```bash
recover_tracking_file() {
    if [ -f "$TRACKING_FILE" ]; then
        if ! jq -e '.' "$TRACKING_FILE" > /dev/null 2>&1; then
            # Main file is corrupted, try backup
            if [ -f "$backup_file" ] && jq -e '.' "$backup_file" > /dev/null 2>&1; then
                cp "$backup_file" "$TRACKING_FILE"
            else
                # No valid backup, start fresh
                echo '{"sessions":[]}' > "$TRACKING_FILE"
            fi
        fi
    fi
}
```

## Behavior After Fix

| Scenario | Before | After |
|----------|--------|-------|
| Crash during write | File corrupted, costs show $0 | Temp file orphaned, original intact |
| Corrupted file detected | Manual fix required | Auto-restore from backup |
| No valid backup | Manual fix required | Fresh start with empty sessions |

## Files Created

- `~/.claude/usage-tracking.json` - Main tracking file
- `~/.claude/usage-tracking.json.bak` - Automatic backup (updated on each write)
- `~/.claude/usage-tracking.json.tmp.*` - Temporary files (cleaned up automatically)

## Manual Recovery

If you need to manually recover from a corrupted file:

```bash
# Check if file is valid
jq '.' ~/.claude/usage-tracking.json

# If invalid, restore from backup
cp ~/.claude/usage-tracking.json.bak ~/.claude/usage-tracking.json

# Or start fresh
echo '{"sessions":[]}' > ~/.claude/usage-tracking.json
```
