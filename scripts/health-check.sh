#!/usr/bin/env bash
# =============================================================================
# health-check.sh — OpenClaw Session Health Report
# Outputs a structured markdown summary of session sizes, rate limit errors,
# and deleted file residue across all agents.
# Usage: ./scripts/health-check.sh
# =============================================================================

set -euo pipefail

AGENTS_DIR="${HOME}/.openclaw/agents"
THRESHOLD_MB=10

echo "# OpenClaw Session Health Report"
echo "_Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')_"
echo ""

# --- Largest Sessions (henri) ------------------------------------------------
echo "## Largest Sessions — henri"
echo ""
echo "\`\`\`"
ls -lSh "${AGENTS_DIR}/henri/sessions/"*.jsonl 2>/dev/null | head -20 \
  || echo "(no sessions found)"
echo "\`\`\`"
echo ""

# Flag any single session > threshold
echo "### ⚠️  Sessions Over ${THRESHOLD_MB}MB"
echo ""
FLAGGED=0
while IFS= read -r file; do
  SIZE_BYTES=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
  SIZE_MB=$(echo "scale=1; $SIZE_BYTES / 1048576" | bc 2>/dev/null || echo "?")
  if [ "$SIZE_BYTES" -gt $((THRESHOLD_MB * 1048576)) ] 2>/dev/null; then
    echo "- **$(basename "$file")** — ${SIZE_MB}MB ⚠️"
    FLAGGED=$((FLAGGED + 1))
  fi
done < <(find "${AGENTS_DIR}/henri/sessions/" -name "*.jsonl" 2>/dev/null)

if [ "$FLAGGED" -eq 0 ]; then
  echo "_No sessions exceed ${THRESHOLD_MB}MB._"
fi
echo ""

# --- Session Sizes by Agent --------------------------------------------------
echo "## Session Storage by Agent"
echo ""
echo "\`\`\`"
du -sh "${AGENTS_DIR}"/*/sessions/ 2>/dev/null | sort -h -r \
  || echo "(no agent session dirs found)"
echo "\`\`\`"
echo ""

# --- Rate Limit Errors -------------------------------------------------------
echo "## Rate Limit Errors (recent sessions)"
echo ""
echo "_Files with 429 / rate-limit hits (descending count):_"
echo ""
echo "\`\`\`"
grep -c "rate.limit\|429\|Too Many" "${AGENTS_DIR}/henri/sessions/"*.jsonl 2>/dev/null \
  | grep -v ':0$' \
  | sort -t: -k2 -rn \
  | head -10 \
  || echo "(none found)"
echo "\`\`\`"
echo ""

# --- Deleted File Residue ----------------------------------------------------
echo "## Deleted Session File Residue"
echo ""

DELETED_COUNT=$(find "${AGENTS_DIR}" -name "*.jsonl.deleted.*" 2>/dev/null | wc -l | tr -d ' ')
DELETED_SIZE=$(find "${AGENTS_DIR}" -name "*.jsonl.deleted.*" 2>/dev/null \
  | xargs du -ch 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")

echo "| Metric | Value |"
echo "|--------|-------|"
echo "| Total deleted files | ${DELETED_COUNT} |"
echo "| Total size | ${DELETED_SIZE} |"
echo ""

STALE_COUNT=$(find "${AGENTS_DIR}" -name "*.jsonl.deleted.*" -mtime +7 2>/dev/null | wc -l | tr -d ' ')
STALE_SIZE=$(find "${AGENTS_DIR}" -name "*.jsonl.deleted.*" -mtime +7 2>/dev/null \
  | xargs du -ch 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")

echo "| Stale (>7 days) | ${STALE_COUNT} files, ${STALE_SIZE} |"
echo ""

if [ "$STALE_COUNT" -gt 0 ]; then
  echo "> 💡 Run \`scripts/cleanup-deleted-sessions.sh --force\` to reclaim ${STALE_SIZE}."
fi
echo ""
echo "---"
echo "_Run \`scripts/workspace-budget.sh\` for full workspace breakdown._"
