#!/bin/bash
# OpenClaw Session Cleanup
# Archives orphaned sessions not referenced in sessions.json
# Usage: bash session-cleanup.sh [agent_name] [agents_dir]

AGENT="${1:-main}"
AGENTS_DIR="${2:-$HOME/.openclaw/agents}"
SESSION_DIR="$AGENTS_DIR/$AGENT/sessions"
ARCHIVE_DIR="$SESSION_DIR/archive/$(date +%Y-%m-%d)"

if [ ! -d "$SESSION_DIR" ]; then
  echo "Error: Session directory not found: $SESSION_DIR"
  exit 1
fi

if [ ! -f "$SESSION_DIR/sessions.json" ]; then
  echo "Error: sessions.json not found in $SESSION_DIR"
  exit 1
fi

mkdir -p "$ARCHIVE_DIR"

echo "═══════════════════════════════════════════"
echo "  Session Cleanup: $AGENT"
echo "  $(date '+%Y-%m-%d %H:%M')"
echo "═══════════════════════════════════════════"

# Count before
BEFORE_COUNT=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" | wc -l | tr -d ' ')
BEFORE_SIZE=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1}END{printf "%.1f", s/1048576}')

echo ""
echo "BEFORE: $BEFORE_COUNT sessions, ${BEFORE_SIZE}MB"
echo ""

# Find and archive orphans
python3 << PYEOF
import json, os, glob, shutil, time

session_dir = "$SESSION_DIR"
archive_dir = "$ARCHIVE_DIR"
sessions_file = os.path.join(session_dir, "sessions.json")

with open(sessions_file) as f:
    data = json.load(f)

# Get referenced session IDs
referenced = set()
for key, val in data.items():
    if isinstance(val, dict):
        fid = val.get('file') or val.get('sessionId')
        if fid:
            referenced.add(fid)

# Move orphaned files
all_files = glob.glob(os.path.join(session_dir, "*.jsonl"))
moved = 0
moved_size = 0
stale_large = 0

for f in all_files:
    name = os.path.basename(f).replace('.jsonl', '')
    is_orphan = name not in referenced
    is_stale_large = (
        os.path.getsize(f) > 10 * 1024 * 1024 and  # >10MB
        time.time() - os.path.getmtime(f) > 7 * 86400  # >7 days old
    )
    
    if is_orphan or is_stale_large:
        size = os.path.getsize(f)
        shutil.move(f, os.path.join(archive_dir, os.path.basename(f)))
        # Move lock file too
        lock = f + '.lock'
        if os.path.exists(lock):
            shutil.move(lock, os.path.join(archive_dir, os.path.basename(lock)))
        moved += 1
        moved_size += size
        if is_stale_large and not is_orphan:
            stale_large += 1

print(f"Archived: {moved} sessions ({moved_size/1024/1024:.1f}MB)")
if stale_large:
    print(f"  (includes {stale_large} stale large sessions)")

# Clean old archives (>30 days)
archive_base = os.path.join(session_dir, "archive")
if os.path.isdir(archive_base):
    cleaned = 0
    for d in os.listdir(archive_base):
        dpath = os.path.join(archive_base, d)
        if os.path.isdir(dpath) and os.path.getmtime(dpath) < time.time() - 30*86400:
            shutil.rmtree(dpath)
            cleaned += 1
    if cleaned:
        print(f"Cleaned {cleaned} old archive(s) (>30 days)")
PYEOF

# Count after
AFTER_COUNT=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" | wc -l | tr -d ' ')
AFTER_SIZE=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1}END{printf "%.1f", s/1048576}')

echo ""
echo "AFTER: $AFTER_COUNT sessions, ${AFTER_SIZE}MB"
echo "═══════════════════════════════════════════"
