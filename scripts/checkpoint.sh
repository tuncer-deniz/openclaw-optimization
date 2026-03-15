#!/bin/bash
# checkpoint.sh — Write session state to memory/session-state.md and daily log
# Usage: checkpoint.sh "task" "exchanges" "pending" [key_files] [tone]
set -euo pipefail

WORKSPACE="${CLAWD_WORKSPACE:-$HOME/clawd}"
STATE_FILE="$WORKSPACE/memory/session-state.md"
DAILY_FILE="$WORKSPACE/memory/$(date +%Y-%m-%d).md"
TIMESTAMP="$(date +'%H:%M %Z')"

TASK="${1:?Usage: checkpoint.sh task exchanges pending [key_files] [tone]}"
EXCHANGES="${2:-No recent exchanges recorded}"
PENDING="${3:-None}"
KEY_FILES="${4:-None}"
TONE="${5:-neutral}"

mkdir -p "$WORKSPACE/memory"

CHECKPOINT="## Checkpoint [$TIMESTAMP]

**Current task:** $TASK
**Last exchanges:** $EXCHANGES
**Pending:** $PENDING
**Key files:** $KEY_FILES
**Tone:** $TONE
"

# Overwrite session-state.md (current state only)
echo "$CHECKPOINT" > "$STATE_FILE"

# Append to daily log
echo "" >> "$DAILY_FILE"
echo "$CHECKPOINT" >> "$DAILY_FILE"

echo "✅ Checkpoint written at $TIMESTAMP"
