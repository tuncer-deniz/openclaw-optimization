#!/bin/bash
# OpenClaw Health Check — Quick system assessment
# Usage: bash health-check.sh [agents_dir] [workspace_dir]

AGENTS_DIR="${1:-$HOME/.openclaw/agents}"
WORKSPACE="${2:-$HOME/clawd}"

echo "═══════════════════════════════════════════"
echo "  OpenClaw Health Check — $(date '+%Y-%m-%d %H:%M')"
echo "═══════════════════════════════════════════"
echo ""

# Session stats
echo "📦 SESSION STATUS"
echo "─────────────────"
total_sessions=0
total_size=0
for dir in "$AGENTS_DIR"/*/sessions; do
  [ -d "$dir" ] || continue
  agent=$(basename "$(dirname "$dir")")
  count=$(find "$dir" -maxdepth 1 -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  size_bytes=$(find "$dir" -maxdepth 1 -name "*.jsonl" -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
  size_mb=$(echo "scale=1; $size_bytes / 1048576" | bc 2>/dev/null || echo "0")
  
  # Health indicator
  if [ "$count" -gt 500 ]; then
    indicator="🔴"
  elif [ "$count" -gt 100 ]; then
    indicator="🟡"
  else
    indicator="🟢"
  fi
  
  echo "  $indicator $agent: $count sessions, ${size_mb}MB"
  total_sessions=$((total_sessions + count))
  total_size=$((total_size + size_bytes))
done
total_mb=$(echo "scale=1; $total_size / 1048576" | bc 2>/dev/null || echo "0")
echo "  ── Total: $total_sessions sessions, ${total_mb}MB"
echo ""

# Orphan check
echo "👻 ORPHAN CHECK"
echo "─────────────────"
for dir in "$AGENTS_DIR"/*/sessions; do
  [ -d "$dir" ] || continue
  [ -f "$dir/sessions.json" ] || continue
  agent=$(basename "$(dirname "$dir")")
  
  total=$(find "$dir" -maxdepth 1 -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  referenced=$(python3 -c "
import json, os
with open('$dir/sessions.json') as f:
    data = json.load(f)
refs = set()
for v in data.values():
    if isinstance(v, dict):
        r = v.get('file') or v.get('sessionId')
        if r: refs.add(r)
print(len(refs))
" 2>/dev/null || echo "?")
  
  orphans=$((total - referenced))
  if [ "$orphans" -gt 50 ]; then
    echo "  🔴 $agent: $orphans orphaned (of $total)"
  elif [ "$orphans" -gt 10 ]; then
    echo "  🟡 $agent: $orphans orphaned (of $total)"
  else
    echo "  🟢 $agent: $orphans orphaned (of $total)"
  fi
done
echo ""

# Workspace context budget
echo "📄 CONTEXT BUDGET (workspace files)"
echo "─────────────────"
ws_total=0
for f in SOUL.md TOOLS.md MEMORY.md AGENTS.md IDENTITY.md USER.md HEARTBEAT.md; do
  filepath="$WORKSPACE/$f"
  if [ -f "$filepath" ]; then
    size=$(wc -c < "$filepath" | tr -d ' ')
    size_kb=$(echo "scale=1; $size / 1024" | bc 2>/dev/null || echo "?")
    ws_total=$((ws_total + size))
    echo "  $f: ${size_kb}KB"
  fi
done
ws_total_kb=$(echo "scale=1; $ws_total / 1024" | bc 2>/dev/null || echo "?")

if [ "$ws_total" -gt 30720 ]; then
  echo "  🔴 Total: ${ws_total_kb}KB (target: <15KB)"
elif [ "$ws_total" -gt 15360 ]; then
  echo "  🟡 Total: ${ws_total_kb}KB (target: <15KB)"
else
  echo "  🟢 Total: ${ws_total_kb}KB"
fi
echo ""

# Large sessions
echo "📏 LARGEST SESSIONS"
echo "─────────────────"
find "$AGENTS_DIR" -name "*.jsonl" -size +1M -exec ls -lh {} \; 2>/dev/null | sort -k5 -h -r | head -5 | while read line; do
  size=$(echo "$line" | awk '{print $5}')
  path=$(echo "$line" | awk '{print $NF}')
  agent=$(echo "$path" | sed "s|$AGENTS_DIR/||" | cut -d/ -f1)
  file=$(basename "$path" .jsonl)
  echo "  ⚠️  $agent/$file: $size"
done
echo ""

echo "═══════════════════════════════════════════"
echo "  Run 'bash scripts/session-cleanup.sh' to fix issues"
echo "═══════════════════════════════════════════"
