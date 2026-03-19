#!/usr/bin/env bash
# camofox-cleanup.sh — Close orphaned Camofox browser tabs left by cron jobs
# Tabs accumulate and cause 429 max-tabs errors.
#
# Usage:
#   bash scripts/camofox-cleanup.sh [--dry-run]
#
# Identifies stale tabs by:
#   - listItemId matching agent:*:cron:* pattern
#   - Tab age older than 1 hour (based on lastActivity or createdAt)

set -euo pipefail

CAMOFOX_API="http://localhost:9377"
DRY_RUN=false
CLOSED=0
SKIPPED=0
AGE_THRESHOLD_SECONDS=3600  # 1 hour

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

NOW=$(date +%s)

echo "═══════════════════════════════════════════"
echo "  Camofox Tab Cleanup — $(date '+%Y-%m-%d %H:%M')"
[ "$DRY_RUN" = true ] && echo "  MODE: DRY RUN (no tabs will be closed)"
echo "═══════════════════════════════════════════"
echo ""

# Check if Camofox API is reachable
if ! curl -sf "$CAMOFOX_API/tabs" > /dev/null 2>&1; then
  echo "⚠️  Camofox API not reachable at $CAMOFOX_API — skipping"
  exit 0
fi

# Fetch all tabs
TABS=$(curl -sf "$CAMOFOX_API/tabs" 2>/dev/null || echo "[]")

if [ "$TABS" = "[]" ] || [ -z "$TABS" ]; then
  echo "🟢 No open tabs found."
  exit 0
fi

TAB_COUNT=$(echo "$TABS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
echo "📋 Total open tabs: $TAB_COUNT"
echo ""

# Process each tab
echo "$TABS" | python3 - <<'PYEOF'
import json, sys, os, subprocess, time

tabs = json.load(sys.stdin)
dry_run = os.environ.get("DRY_RUN", "false") == "true"
api = os.environ.get("CAMOFOX_API", "http://localhost:9377")
age_threshold = int(os.environ.get("AGE_THRESHOLD_SECONDS", "3600"))
now = int(time.time())

closed = 0
skipped = 0
errors = 0

for tab in tabs:
    tab_id = tab.get("id") or tab.get("tabId") or tab.get("sessionId", "")
    list_item_id = tab.get("listItemId", "") or tab.get("sessionKey", "") or ""
    url = tab.get("url", "unknown")
    title = tab.get("title", "")[:60]

    # Determine tab age
    created_raw = tab.get("createdAt") or tab.get("lastActivity") or tab.get("openedAt")
    tab_age_seconds = None
    if created_raw:
        try:
            # Handle ISO format and epoch milliseconds
            if isinstance(created_raw, (int, float)):
                ts = created_raw / 1000 if created_raw > 1e10 else created_raw
            else:
                from datetime import datetime
                ts = datetime.fromisoformat(created_raw.replace("Z", "+00:00")).timestamp()
            tab_age_seconds = now - int(ts)
        except Exception:
            tab_age_seconds = None

    # Determine if stale
    is_cron_tab = False
    if list_item_id:
        import re
        is_cron_tab = bool(re.match(r"agent:[^:]+:cron:", list_item_id))

    is_old = tab_age_seconds is not None and tab_age_seconds > age_threshold

    should_close = is_cron_tab or is_old

    if not should_close:
        skipped += 1
        continue

    reason_parts = []
    if is_cron_tab:
        reason_parts.append(f"cron tab (listItemId={list_item_id})")
    if is_old:
        age_min = tab_age_seconds // 60
        reason_parts.append(f"age={age_min}m")

    reason = ", ".join(reason_parts)

    if dry_run:
        print(f"  🔵 [DRY RUN] Would close: {title or url} — {reason}")
        closed += 1
    else:
        try:
            result = subprocess.run(
                ["curl", "-sf", "-X", "DELETE", f"{api}/tabs/{tab_id}"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                print(f"  ✅ Closed: {title or url} — {reason}")
                closed += 1
            else:
                print(f"  ⚠️  Failed to close {tab_id}: {result.stderr.strip()}")
                errors += 1
        except Exception as e:
            print(f"  ⚠️  Error closing {tab_id}: {e}")
            errors += 1

print()
print(f"📊 Summary: {closed} closed, {skipped} kept, {errors} errors")
if dry_run and closed > 0:
    print("   (re-run without --dry-run to actually close these tabs)")
PYEOF

exit 0
