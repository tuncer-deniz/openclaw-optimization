#!/usr/bin/env python3
"""Find orphaned session files not referenced in sessions.json."""

import json
import os
import glob
import sys

def find_orphans(sessions_dir):
    sessions_file = os.path.join(sessions_dir, "sessions.json")
    
    if not os.path.exists(sessions_file):
        print(f"Error: {sessions_file} not found")
        sys.exit(1)
    
    with open(sessions_file) as f:
        data = json.load(f)
    
    # Get referenced IDs
    referenced = set()
    for key, val in data.items():
        if isinstance(val, dict):
            fid = val.get('file') or val.get('sessionId')
            if fid:
                referenced.add(fid)
    
    # Find all .jsonl files
    all_files = glob.glob(os.path.join(sessions_dir, "*.jsonl"))
    
    orphans = []
    orphan_size = 0
    for f in all_files:
        name = os.path.basename(f).replace('.jsonl', '')
        if name not in referenced:
            size = os.path.getsize(f)
            orphans.append((name, size, f))
            orphan_size += size
    
    # Report
    print(f"Referenced in sessions.json: {len(referenced)}")
    print(f"Total .jsonl files: {len(all_files)}")
    print(f"Orphaned: {len(orphans)} ({orphan_size/1024/1024:.1f}MB)")
    
    if orphans:
        print("\nOrphaned files (sorted by size):")
        for name, size, path in sorted(orphans, key=lambda x: -x[1])[:20]:
            print(f"  {size/1024:.0f}KB  {name}")
        if len(orphans) > 20:
            print(f"  ... and {len(orphans)-20} more")

if __name__ == "__main__":
    sessions_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.openclaw/agents/main/sessions")
    find_orphans(sessions_dir)
