# OpenClaw Optimization Skill

Systematic performance optimization for OpenClaw AI agents. Covers session management, context budget optimization, token tracking, and automated maintenance.

## When to Use
- Agent feels sluggish or responses are slow
- Context window is filling up (check with `/status`)
- Token costs are higher than expected
- Setting up a new agent or onboarding to multi-agent setup
- Periodic maintenance (weekly/monthly)

## Quick Health Check

Run this first to assess current state:

```bash
bash scripts/health-check.sh
```

Or manually:

```bash
# Session count and size per agent
for dir in ~/.openclaw/agents/*/sessions; do
  agent=$(basename $(dirname "$dir"))
  count=$(ls "$dir"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
  size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
  echo "$agent: $count sessions, $size"
done

# Context budget (workspace files loaded every message)
for f in SOUL.md TOOLS.md MEMORY.md AGENTS.md IDENTITY.md USER.md; do
  [ -f "$f" ] && echo "$f: $(wc -c < "$f" | tr -d ' ') bytes"
done
```

### What Good Looks Like
| Metric | 🟢 Healthy | 🟡 Watch | 🔴 Action Needed |
|--------|-----------|----------|-------------------|
| Active sessions | <100 | 100-500 | >500 |
| Largest session | <5MB | 5-15MB | >15MB |
| Total session size | <50MB | 50-150MB | >150MB |
| Workspace files total | <15KB | 15-30KB | >30KB |
| Context usage | <60% | 60-80% | >80% |

## Phase 1: Session Cleanup

### Identify Orphaned Sessions
Sessions accumulate from sub-agents, cron jobs, and completed tasks. Most are orphaned (not referenced in `sessions.json`).

```bash
bash scripts/session-cleanup.sh
```

The script:
1. Reads `sessions.json` for referenced session IDs
2. Moves unreferenced `.jsonl` files to `archive/YYYY-MM-DD/`
3. Identifies stale large sessions (>10MB, not modified in 7+ days)
4. Cleans archives older than 30 days

### Manual Cleanup (if needed)
```bash
# Find orphaned sessions
python3 scripts/find-orphans.py ~/.openclaw/agents/main/sessions/

# Archive a specific stale session
mv ~/.openclaw/agents/main/sessions/SESSION_ID.jsonl \
   ~/.openclaw/agents/main/sessions/archive/
```

### Protect Active Sessions
Never archive sessions referenced in `sessions.json`. These are:
- Channel sessions (Discord, Telegram, Slack)
- Active cron job sessions
- Sub-agent sessions still running

## Phase 2: Context Budget Optimization

Every message loads all workspace files. Smaller files = faster responses + lower cost.

### File-by-File Guidelines

**SOUL.md** — Target: <2KB
- Personality, tone, communication rules only
- No tool instructions, no project details
- If it's >50 lines, it's too long

**TOOLS.md** — Target: <4KB
- Only tools you actively use
- Remove placeholder configs (e.g., "replace with actual token")
- Move rare-use tool docs to skills

**MEMORY.md** — Target: <6KB
- Active projects and current state only
- Archive resolved issues and completed one-offs
- Consolidate duplicate entries
- Move historical details to `memory/` daily logs

**AGENTS.md** — Target: <4KB
- Agent routing rules and channel mappings
- Remove verbose examples — keep terse rules
- Cross-agent config → reference only (don't duplicate full configs)

**IDENTITY.md** — Target: <500 bytes
- Name, emoji, one-liner personality. That's it.

**USER.md** — Target: <1KB
- Essential preferences and context about the human

### Optimization Prompt
Run this against any file to get trim suggestions:

```
Review this file for an AI agent's context window. Identify:
1. Redundant information (said twice differently)
2. Stale content (resolved issues, completed tasks, old dates)
3. Verbose language (could be said in fewer words)
4. Content that belongs in a skill (only needed sometimes)
Suggest a trimmed version that preserves all critical operational info.
```

## Phase 3: Token Usage Tracking

```bash
bash scripts/token-tracker.sh
```

Logs to `memory/token-usage-log.jsonl`:
- Per-agent session counts and sizes
- Workspace file sizes (context budget)
- Timestamp for trend analysis

### Reading the Logs
```bash
# Latest entry
tail -1 memory/token-usage-log.jsonl | python3 -m json.tool

# Trend: workspace size over time
cat memory/token-usage-log.jsonl | python3 -c "
import json, sys
for line in sys.stdin:
    entry = json.loads(line)
    ts = entry['timestamp'][:10]
    ws = entry.get('workspace_total_kb', '?')
    sessions = sum(a['session_count'] for a in entry['agents'].values())
    print(f'{ts}: {ws}KB workspace, {sessions} sessions')
"
```

## Phase 4: Automation

### Recommended Cron Schedule

| Job | Schedule | Command |
|-----|----------|---------|
| Session cleanup | Weekly (Sun 3 AM) | `bash scripts/session-cleanup.sh` |
| Token tracking | Daily (6 AM) | `bash scripts/token-tracker.sh` |
| Workspace audit | Monthly (1st, 9 AM) | Manual review prompted by cron |

### OpenClaw Cron Setup
```bash
# Weekly session cleanup
openclaw cron add \
  --name "weekly-session-cleanup" \
  --cron "0 3 * * 0" \
  --tz "America/Edmonton" \
  --agent main \
  --session isolated \
  --timeout-seconds 120 \
  --message "Run: bash ~/clawd/tools/session-cleanup.sh && bash ~/clawd/tools/token-usage-tracker.sh. Post before/after stats summary." \
  --announce

# Daily token tracking
openclaw cron add \
  --name "daily-token-tracking" \
  --cron "0 6 * * *" \
  --tz "America/Edmonton" \
  --agent main \
  --session isolated \
  --timeout-seconds 60 \
  --message "Run: bash ~/clawd/tools/token-usage-tracker.sh"
```

## Phase 5: Multi-Agent Optimization

When running multiple agents (Henri, Luna, Atlas, etc.):

1. **Each agent needs independent cleanup** — sessions are per-agent, per-machine
2. **Coordinate via shared channel** — post before/after stats to a coordination channel
3. **Stagger cron jobs** — don't run all cleanups at the same time
4. **Shared learnings** — when one agent finds a bloat pattern, document it for all

### Cross-Agent Cleanup Command
For agents you can reach via LAN API:
```bash
curl -X POST http://AGENT_IP:18789/v1/chat/completions \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"openclaw:MODEL","messages":[{"role":"user","content":"Run session cleanup: archive orphaned sessions not in sessions.json, report before/after stats."}]}'
```

## Troubleshooting

### "Resource deadlock avoided" on files
iCloud-synced files can lock. Fix: `brctl download /path/to/file` then retry.

### Sessions.json out of sync
If sessions.json references files that don't exist, the gateway may create empty replacements. Clean up:
```python
# Remove entries pointing to nonexistent files
python3 scripts/fix-sessions-json.py
```

### Context at 80%+ after optimization
- Check for large tool call results cached in session
- Context pruning setting: `contextPruning.mode: "cache-ttl"`, `ttl: "30m"`
- Consider `compaction.mode: "default"` for automatic context management

### Gateway slow after cleanup
Restart: `openclaw gateway restart`

## Success Metrics
After full optimization:
- [ ] All workspace files under target sizes
- [ ] <100 active sessions per agent
- [ ] Weekly cleanup cron running
- [ ] Daily token tracking logging
- [ ] Context usage <60% at session start
- [ ] Month-over-month cost trending down (or stable)
