#!/usr/bin/env bash
# =============================================================================
# workspace-budget.sh — Clawd Workspace Disk Budget Report
# Outputs a structured markdown summary of disk usage across key directories,
# flags oversized dirs, and lists the top 10 largest files.
# Usage: ./scripts/workspace-budget.sh
# =============================================================================

set -euo pipefail

CLAWD="${HOME}/clawd"
WARN_THRESHOLD_GB=5

echo "# Workspace Budget Report"
echo "_Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')_"
echo ""

# --- Total workspace size ----------------------------------------------------
TOTAL=$(du -sh "${CLAWD}" 2>/dev/null | awk '{print $1}')
echo "## Total Workspace Size: \`${TOTAL}\`"
echo ""

# --- Per-directory breakdown -------------------------------------------------
echo "## Key Directory Sizes"
echo ""
echo "| Directory | Size | Status |"
echo "|-----------|------|--------|"

KEY_DIRS=(
  "tools"
  "projects"
  "memory"
  "research"
  "skills"
  "data"
)

for dir in "${KEY_DIRS[@]}"; do
  FULL="${CLAWD}/${dir}"
  if [ -d "$FULL" ]; then
    SIZE=$(du -sh "$FULL" 2>/dev/null | awk '{print $1}')
    # Extract numeric GB for threshold check (rough comparison)
    SIZE_BYTES=$(du -sb "$FULL" 2>/dev/null | awk '{print $1}' || echo 0)
    if [ "$SIZE_BYTES" -gt $((WARN_THRESHOLD_GB * 1073741824)) ] 2>/dev/null; then
      STATUS="⚠️ OVER ${WARN_THRESHOLD_GB}GB"
    else
      STATUS="✅ ok"
    fi
    echo "| \`${dir}/\` | ${SIZE} | ${STATUS} |"
  else
    echo "| \`${dir}/\` | _(not found)_ | — |"
  fi
done
echo ""

# --- Top 10 largest files ----------------------------------------------------
echo "## Top 10 Largest Files"
echo "_(excluding .git and node_modules)_"
echo ""
echo "\`\`\`"
find "${CLAWD}" \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  -type f \
  -exec du -sh {} + 2>/dev/null \
  | sort -rh \
  | head -10
echo "\`\`\`"
echo ""

# --- Also check ~/.openclaw agent storage ------------------------------------
echo "## Agent Session Storage (~/.openclaw)"
echo ""
echo "\`\`\`"
du -sh ~/.openclaw/agents/*/sessions/ 2>/dev/null | sort -rh || echo "(none)"
echo "\`\`\`"
echo ""
TOTAL_OC=$(du -sh ~/.openclaw 2>/dev/null | awk '{print $1}')
echo "_Total ~/.openclaw: **${TOTAL_OC}**_"
echo ""
echo "---"
echo "_Run \`scripts/health-check.sh\` for session-level diagnostics._"
