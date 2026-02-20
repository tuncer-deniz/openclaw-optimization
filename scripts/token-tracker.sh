#!/bin/bash
# OpenClaw Token Usage Tracker
# Logs per-agent session stats and workspace file sizes
# Usage: bash token-tracker.sh [workspace_dir] [agents_dir]

WORKSPACE="${1:-$HOME/clawd}"
AGENTS_DIR="${2:-$HOME/.openclaw/agents}"
TRACK_FILE="$WORKSPACE/memory/token-usage-log.jsonl"

mkdir -p "$(dirname "$TRACK_FILE")"

python3 << PYEOF
import json, os, glob
from datetime import datetime

workspace = "$WORKSPACE"
agents_dir = "$AGENTS_DIR"
track_file = "$TRACK_FILE"

entry = {
    "timestamp": datetime.utcnow().isoformat() + "Z",
    "agents": {},
    "workspace_files": {},
    "workspace_total_kb": 0
}

# Per-agent stats
for agent_dir in sorted(glob.glob(os.path.join(agents_dir, "*"))):
    if not os.path.isdir(agent_dir):
        continue
    agent = os.path.basename(agent_dir)
    sessions_dir = os.path.join(agent_dir, "sessions")
    if not os.path.isdir(sessions_dir):
        continue
    
    jsonl_files = glob.glob(os.path.join(sessions_dir, "*.jsonl"))
    total_size = sum(os.path.getsize(f) for f in jsonl_files)
    largest = max((os.path.getsize(f) for f in jsonl_files), default=0)
    
    entry["agents"][agent] = {
        "session_count": len(jsonl_files),
        "total_size_mb": round(total_size / 1024 / 1024, 2),
        "largest_session_mb": round(largest / 1024 / 1024, 2)
    }

# Workspace file sizes
ws_total = 0
for f in ["SOUL.md", "TOOLS.md", "MEMORY.md", "AGENTS.md", "IDENTITY.md", "USER.md", "HEARTBEAT.md"]:
    path = os.path.join(workspace, f)
    if os.path.exists(path):
        size = os.path.getsize(path)
        entry["workspace_files"][f] = round(size / 1024, 1)
        ws_total += size

entry["workspace_total_kb"] = round(ws_total / 1024, 1)

# Write
with open(track_file, "a") as fh:
    fh.write(json.dumps(entry) + "\n")

# Print summary
print(f"📊 Token tracker logged at {entry['timestamp'][:19]}")
print(f"   Workspace: {entry['workspace_total_kb']}KB across {len(entry['workspace_files'])} files")
for agent, data in sorted(entry["agents"].items()):
    if data["session_count"] > 0:
        print(f"   {agent}: {data['session_count']} sessions, {data['total_size_mb']}MB (largest: {data['largest_session_mb']}MB)")
PYEOF
