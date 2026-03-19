#!/usr/bin/env bash
# workspace-budget.sh — Track workspace context file sizes over time
# Alerts when files are growing too large (wastes context budget every message)
#
# Usage:
#   bash scripts/workspace-budget.sh
#
# Logs to: ~/.openclaw/workspace-budget.csv
# Thresholds: warn at 15KB, critical at 25KB

set -euo pipefail

WORKSPACE="${WORKSPACE:-$HOME/clawd}"
CSV_FILE="$HOME/.openclaw/workspace-budget.csv"
WARN_KB=15
CRIT_KB=25

# Files to track
FILES=(
  SOUL.md
  TOOLS.md
  MEMORY.md
  AGENTS.md
  IDENTITY.md
  USER.md
  BRAIN.md
  HEARTBEAT.md
  BOOTSTRAP.md
)

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "═══════════════════════════════════════════"
echo "  Workspace Budget — $(date '+%Y-%m-%d %H:%M')"
echo "═══════════════════════════════════════════"
echo ""

# Ensure CSV dir exists
mkdir -p "$(dirname "$CSV_FILE")"

# Write CSV header if new file
if [ ! -f "$CSV_FILE" ]; then
  echo "timestamp,file,bytes,kb" > "$CSV_FILE"
fi

# Load last CSV entry for trend comparison
get_last_size() {
  local fname="$1"
  # last line matching this file
  grep ",$fname," "$CSV_FILE" 2>/dev/null | tail -1 | awk -F',' '{print $3}' || echo ""
}

TOTAL_BYTES=0
WARN_COUNT=0
CRIT_COUNT=0

echo "📄 CONTEXT BUDGET (workspace files)"
echo "─────────────────────────────────────"

for fname in "${FILES[@]}"; do
  fpath="$WORKSPACE/$fname"

  if [ ! -f "$fpath" ]; then
    echo "  ⚫ $fname: not found"
    continue
  fi

  bytes=$(wc -c < "$fpath" | tr -d ' ')
  kb_raw=$(echo "scale=1; $bytes / 1024" | bc)
  kb_int=$(echo "$bytes / 1024" | bc)

  TOTAL_BYTES=$((TOTAL_BYTES + bytes))

  # Trend
  last_bytes=$(get_last_size "$fname")
  trend=""
  if [ -n "$last_bytes" ] && [ "$last_bytes" -ne 0 ]; then
    delta=$((bytes - last_bytes))
    if [ $delta -gt 512 ]; then
      trend=" ↑ (+$(echo "scale=1; $delta/1024" | bc)KB)"
    elif [ $delta -lt -512 ]; then
      trend=" ↓ ($(echo "scale=1; $delta/1024" | bc)KB)"
    else
      trend=" →"
    fi
  fi

  # Traffic light
  if [ "$kb_int" -ge "$CRIT_KB" ]; then
    icon="🔴"
    CRIT_COUNT=$((CRIT_COUNT + 1))
  elif [ "$kb_int" -ge "$WARN_KB" ]; then
    icon="🟡"
    WARN_COUNT=$((WARN_COUNT + 1))
  else
    icon="🟢"
  fi

  printf "  %s %-16s %6s KB%s\n" "$icon" "$fname" "$kb_raw" "$trend"

  # Append to CSV
  echo "$TIMESTAMP,$fname,$bytes,$kb_raw" >> "$CSV_FILE"
done

TOTAL_KB_RAW=$(echo "scale=1; $TOTAL_BYTES / 1024" | bc)
TOTAL_KB_INT=$(echo "$TOTAL_BYTES / 1024" | bc)
echo ""
echo "─────────────────────────────────────"

if [ "$TOTAL_KB_INT" -ge $((CRIT_KB * 4)) ]; then
  TOTAL_ICON="🔴"
elif [ "$TOTAL_KB_INT" -ge $((WARN_KB * 4)) ]; then
  TOTAL_ICON="🟡"
else
  TOTAL_ICON="🟢"
fi

printf "  %s %-16s %6s KB (total)\n" "$TOTAL_ICON" "TOTAL" "$TOTAL_KB_RAW"
echo ""

# Summary
if [ "$CRIT_COUNT" -gt 0 ]; then
  echo "🔴 CRITICAL: $CRIT_COUNT file(s) over ${CRIT_KB}KB — trim immediately to reduce context cost"
elif [ "$WARN_COUNT" -gt 0 ]; then
  echo "🟡 WARNING: $WARN_COUNT file(s) over ${WARN_KB}KB — consider trimming"
else
  echo "🟢 All files within budget"
fi

echo ""
echo "📈 History logged to: $CSV_FILE"

# Show trend summary from last 7 entries
HISTORY_LINES=$(grep -c "," "$CSV_FILE" 2>/dev/null || echo 0)
if [ "$HISTORY_LINES" -gt 10 ]; then
  echo ""
  echo "📊 Recent total size trend:"
  python3 - "$CSV_FILE" <<'PYEOF'
import sys, csv
from collections import defaultdict

path = sys.argv[1]
by_ts = defaultdict(int)

with open(path) as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            by_ts[row["timestamp"]] += int(row["bytes"])
        except (ValueError, KeyError):
            pass

entries = sorted(by_ts.items())[-7:]
for ts, total in entries:
    kb = total / 1024
    bar = "█" * int(kb / 5)
    print(f"  {ts[:10]}  {kb:6.1f}KB  {bar}")
PYEOF
fi

exit 0
