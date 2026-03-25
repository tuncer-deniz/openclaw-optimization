#!/usr/bin/env bash
# =============================================================================
# cleanup-deleted-sessions.sh — Clean up stale deleted session files
# Finds *.jsonl.deleted.* files older than 7 days in ~/.openclaw/agents/
# Dry-run by default. Pass --force to actually delete.
# Usage:
#   ./scripts/cleanup-deleted-sessions.sh          # dry run (safe)
#   ./scripts/cleanup-deleted-sessions.sh --force  # actually delete
# =============================================================================

set -euo pipefail

AGENTS_DIR="${HOME}/.openclaw/agents"
DAYS_OLD=7
FORCE=false

# --- Parse args --------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --help|-h)
      echo "Usage: $0 [--force]"
      echo "  Default: dry run — shows what would be deleted."
      echo "  --force: actually deletes files older than ${DAYS_OLD} days."
      exit 0
      ;;
  esac
done

echo "# Cleanup: Deleted Session Files"
echo "_Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')_"
echo ""

# --- Discover stale files ----------------------------------------------------
STALE_FILES=$(find "${AGENTS_DIR}" -name "*.jsonl.deleted.*" -mtime +${DAYS_OLD} 2>/dev/null)
STALE_COUNT=$(echo "$STALE_FILES" | grep -c . 2>/dev/null || echo 0)

if [ -z "$STALE_FILES" ]; then
  echo "✅ No stale deleted session files found (older than ${DAYS_OLD} days)."
  exit 0
fi

# Before size
BEFORE_SIZE=$(echo "$STALE_FILES" | xargs du -ch 2>/dev/null | tail -1 | awk '{print $1}')
TOTAL_AGENTS_BEFORE=$(du -sh "${AGENTS_DIR}" 2>/dev/null | awk '{print $1}')

echo "## Files to be removed (>${DAYS_OLD} days old)"
echo ""
echo "| File | Size |"
echo "|------|------|"
echo "$STALE_FILES" | while read -r f; do
  [ -z "$f" ] && continue
  SZ=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
  echo "| \`$(basename "$f")\` | ${SZ} |"
done
echo ""
echo "**Total:** ${STALE_COUNT} files, **${BEFORE_SIZE}** reclaimable"
echo ""

# --- Execute or report -------------------------------------------------------
if [ "$FORCE" = true ]; then
  echo "## Deleting..."
  echo ""
  echo "$STALE_FILES" | xargs rm -f
  AFTER_SIZE=$(du -sh "${AGENTS_DIR}" 2>/dev/null | awk '{print $1}')
  echo "✅ Deleted ${STALE_COUNT} files."
  echo ""
  echo "| | Before | After |"
  echo "|-|--------|-------|"
  echo "| agents/ total | ${TOTAL_AGENTS_BEFORE} | ${AFTER_SIZE} |"
else
  echo "> 🔒 **Dry run** — no files deleted."
  echo "> Re-run with \`--force\` to actually delete **${BEFORE_SIZE}** of stale data."
fi
