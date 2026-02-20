#!/usr/bin/env python3
"""Fix sessions.json by removing entries that point to nonexistent files."""

import json
import os
import sys

def fix_sessions(sessions_dir):
    sessions_file = os.path.join(sessions_dir, "sessions.json")
    
    if not os.path.exists(sessions_file):
        print(f"Error: {sessions_file} not found")
        sys.exit(1)
    
    with open(sessions_file) as f:
        data = json.load(f)
    
    original_count = len(data)
    to_remove = []
    
    for key, val in data.items():
        if isinstance(val, dict):
            fid = val.get('file') or val.get('sessionId')
            if fid:
                jsonl_path = os.path.join(sessions_dir, f"{fid}.jsonl")
                if not os.path.exists(jsonl_path):
                    to_remove.append(key)
    
    if not to_remove:
        print(f"sessions.json is clean ({original_count} entries, all files exist)")
        return
    
    # Backup
    backup = sessions_file + ".bak"
    with open(backup, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Backed up to {backup}")
    
    # Remove stale entries
    for key in to_remove:
        del data[key]
    
    with open(sessions_file, 'w') as f:
        json.dump(data, f, indent=2)
    
    print(f"Removed {len(to_remove)} stale entries (had {original_count}, now {len(data)})")
    for key in to_remove:
        print(f"  - {key}")

if __name__ == "__main__":
    sessions_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.openclaw/agents/main/sessions")
    fix_sessions(sessions_dir)
