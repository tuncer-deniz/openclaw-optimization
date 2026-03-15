#!/bin/bash
# OpenClaw Session Cleanup v2
# Smart retention: keeps persistent channels, archives completed work
# Usage: bash session-cleanup.sh [agent_name] [agents_dir] [--dry-run]

AGENT="${1:-main}"
AGENTS_DIR="${2:-$HOME/.openclaw/agents}"
DRY_RUN=""
[[ "$*" == *"--dry-run"* ]] && DRY_RUN="true"

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

[ -z "$DRY_RUN" ] && mkdir -p "$ARCHIVE_DIR"

echo "═══════════════════════════════════════════"
echo "  Session Cleanup v3: $AGENT"
echo "  $(date '+%Y-%m-%d %H:%M')"
[ -n "$DRY_RUN" ] && echo "  MODE: DRY RUN (no changes)"
echo "═══════════════════════════════════════════"

# Phase 0: Clean orphaned .tmp files (atomic write leftovers)
TMP_COUNT=$(find "$SESSION_DIR" -maxdepth 1 -name "sessions.json.*.tmp" 2>/dev/null | wc -l | tr -d ' ')
if [ "$TMP_COUNT" -gt 0 ]; then
  TMP_SIZE=$(find "$SESSION_DIR" -maxdepth 1 -name "sessions.json.*.tmp" -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1}END{printf "%.1f", s/1048576}')
  echo ""
  echo "ORPHANED TMP FILES: $TMP_COUNT (${TMP_SIZE}MB)"
  if [ -z "$DRY_RUN" ]; then
    find "$SESSION_DIR" -maxdepth 1 -name "sessions.json.*.tmp" -delete
    echo "  ✓ Removed"
  else
    echo "  [DRY RUN] Would remove"
  fi
fi

# Phase 0b: Prune sessions.json — remove entries pointing to nonexistent files
if [ -z "$DRY_RUN" ]; then
  PRUNED=$(python3 -c "
import json, os
sf = '$SESSION_DIR/sessions.json'
with open(sf) as f:
    data = json.load(f)
before = len(data)
kept = {k:v for k,v in data.items() if v.get('sessionFile') and os.path.exists(v['sessionFile'])}
if len(kept) < before:
    with open(sf, 'w') as f:
        json.dump(kept, f, indent=2)
print(f'{before - len(kept)}')
" 2>/dev/null)
  if [ "$PRUNED" -gt 0 ] 2>/dev/null; then
    echo ""
    echo "SESSIONS.JSON PRUNED: $PRUNED orphan entries removed"
  fi
fi

# Count before
BEFORE_COUNT=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" | wc -l | tr -d ' ')
BEFORE_SIZE=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1}END{printf "%.1f", s/1048576}')

echo ""
echo "BEFORE: $BEFORE_COUNT sessions, ${BEFORE_SIZE}MB"
echo ""

# Find and archive based on retention policy
python3 << PYEOF
import json, os, glob, shutil, time, re

session_dir = "$SESSION_DIR"
archive_dir = "$ARCHIVE_DIR"
dry_run = bool("$DRY_RUN")
sessions_file = os.path.join(session_dir, "sessions.json")

# Retention policy (in hours)
RETENTION = {
    'persistent_channel': float('inf'),  # Never archive
    'completed_subagent': 24,             # 24h after completion
    'cron_session': 24,                   # 24h
    'stale_any': 48,                      # Anything untouched 48h
    'large_stale': 168,                   # Large files (>5MB) after 7 days
}

with open(sessions_file) as f:
    data = json.load(f)

# Get referenced session IDs with metadata
referenced = {}
for key, val in data.items():
    if isinstance(val, dict):
        fid = val.get('file') or val.get('sessionId')
        if fid:
            referenced[fid] = {
                'key': key,
                'kind': val.get('kind', 'unknown'),
                'lastUpdatedAt': val.get('lastUpdatedAt'),
                'endedAt': val.get('endedAt'),
                'metadata': val.get('metadata', {})
            }

def is_persistent_channel(key, meta):
    """Check if this is a persistent Discord/Telegram channel session"""
    if not key:
        return False
    # Pattern: agent:main:discord:channel:ID or agent:main:telegram:ID
    patterns = [
        r'agent:\w+:discord:channel:\d+',
        r'agent:\w+:telegram:-?\d+',
        r'agent:\w+:signal:',
        r'agent:\w+:slack:',
    ]
    return any(re.match(p, key) for p in patterns)

def is_cron_session(key, meta):
    """Check if this is an isolated cron job session"""
    if not key:
        return False
    return ':cron:' in key or meta.get('kind') == 'cron'

def get_session_age_hours(filepath, meta):
    """Get age in hours based on lastUpdatedAt or file mtime"""
    last_updated = meta.get('lastUpdatedAt')
    if last_updated:
        try:
            # Parse ISO timestamp
            from datetime import datetime
            dt = datetime.fromisoformat(last_updated.replace('Z', '+00:00'))
            age_sec = time.time() - dt.timestamp()
            return age_sec / 3600
        except:
            pass
    # Fallback to file mtime
    if os.path.exists(filepath):
        return (time.time() - os.path.getmtime(filepath)) / 3600
    return float('inf')

def should_archive(name, filepath, meta):
    """Determine if session should be archived and why"""
    key = meta.get('key', '')
    age_hours = get_session_age_hours(filepath, meta)
    size_mb = os.path.getsize(filepath) / 1024 / 1024 if os.path.exists(filepath) else 0
    
    # Never archive persistent channels
    if is_persistent_channel(key, meta):
        return False, "persistent_channel"
    
    # Orphaned (not in sessions.json)
    if not meta:
        if age_hours > RETENTION['stale_any']:
            return True, f"orphan_stale_{age_hours:.0f}h"
        return False, "orphan_recent"
    
    # Cron sessions - aggressive cleanup
    if is_cron_session(key, meta):
        if age_hours > RETENTION['cron_session']:
            return True, f"cron_{age_hours:.0f}h"
        return False, "cron_recent"
    
    # Completed subagents (has endedAt)
    if meta.get('endedAt'):
        if age_hours > RETENTION['completed_subagent']:
            return True, f"completed_{age_hours:.0f}h"
        return False, "completed_recent"
    
    # Large stale files
    if size_mb > 5 and age_hours > RETENTION['large_stale']:
        return True, f"large_stale_{size_mb:.1f}MB_{age_hours:.0f}h"
    
    # General stale
    if age_hours > RETENTION['stale_any']:
        return True, f"stale_{age_hours:.0f}h"
    
    return False, "active"

# Process all files
all_files = glob.glob(os.path.join(session_dir, "*.jsonl"))
to_archive = []
kept = {'persistent_channel': 0, 'active': 0, 'recent': 0}

for f in all_files:
    name = os.path.basename(f).replace('.jsonl', '')
    meta = referenced.get(name, {})
    
    archive, reason = should_archive(name, f, meta)
    size = os.path.getsize(f) if os.path.exists(f) else 0
    
    if archive:
        to_archive.append({'path': f, 'name': name, 'reason': reason, 'size': size})
    else:
        if 'persistent' in reason:
            kept['persistent_channel'] += 1
        elif 'recent' in reason:
            kept['recent'] += 1
        else:
            kept['active'] += 1

# Show what will be archived
print(f"RETENTION POLICY:")
print(f"  Persistent channels: keep forever")
print(f"  Completed subagents: {RETENTION['completed_subagent']}h")
print(f"  Cron sessions: {RETENTION['cron_session']}h")
print(f"  Stale sessions: {RETENTION['stale_any']}h")
print(f"  Large stale (>5MB): {RETENTION['large_stale']}h")
print()

print(f"KEEPING: {len(all_files) - len(to_archive)} sessions")
print(f"  Persistent channels: {kept['persistent_channel']}")
print(f"  Recently active: {kept['recent']}")
print(f"  Other active: {kept['active']}")
print()

if to_archive:
    total_size = sum(x['size'] for x in to_archive)
    print(f"ARCHIVING: {len(to_archive)} sessions ({total_size/1024/1024:.1f}MB)")
    
    # Group by reason
    by_reason = {}
    for x in to_archive:
        r = x['reason'].split('_')[0]
        by_reason[r] = by_reason.get(r, 0) + 1
    for r, c in sorted(by_reason.items()):
        print(f"  {r}: {c}")
    
    if not dry_run:
        for x in to_archive:
            shutil.move(x['path'], os.path.join(archive_dir, os.path.basename(x['path'])))
            lock = x['path'] + '.lock'
            if os.path.exists(lock):
                shutil.move(lock, os.path.join(archive_dir, os.path.basename(lock)))
        print(f"\n✓ Archived to: {archive_dir}")
    else:
        print(f"\n[DRY RUN] Would archive to: {archive_dir}")
else:
    print("ARCHIVING: Nothing to archive")

# Clean old archives (>30 days)
archive_base = os.path.join(session_dir, "archive")
if os.path.isdir(archive_base) and not dry_run:
    cleaned = 0
    for d in os.listdir(archive_base):
        dpath = os.path.join(archive_base, d)
        if os.path.isdir(dpath) and os.path.getmtime(dpath) < time.time() - 30*86400:
            shutil.rmtree(dpath)
            cleaned += 1
    if cleaned:
        print(f"\nCleaned {cleaned} old archive(s) (>30 days)")
PYEOF

# Count after (only if not dry run)
if [ -z "$DRY_RUN" ]; then
    AFTER_COUNT=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" | wc -l | tr -d ' ')
    AFTER_SIZE=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1}END{printf "%.1f", s/1048576}')
    echo ""
    echo "AFTER: $AFTER_COUNT sessions, ${AFTER_SIZE}MB"
fi

echo "═══════════════════════════════════════════"
