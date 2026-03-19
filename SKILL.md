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

### Smart Retention Policy (v2)

Sessions accumulate from sub-agents, cron jobs, and completed tasks. The v2 cleanup script uses intelligent retention based on session type:

| Session Type | Retention | Rationale |
|--------------|-----------|-----------|
| Persistent channels (#henri, telegram, etc.) | Forever | Continuity — compaction handles size |
| Completed sub-agents | 24 hours | Debugging window only |
| Cron job sessions | 24 hours | Each run is isolated |
| Any stale session | 48 hours | If untouched, it's dead |
| Large stale (>5MB) | 7 days | Extra buffer for big sessions |

### Run Cleanup

```bash
# Preview what would be archived (safe)
bash scripts/session-cleanup.sh main ~/.openclaw/agents --dry-run

# Actually archive
bash scripts/session-cleanup.sh
```

The script:
1. Identifies session type (channel, sub-agent, cron, etc.) from `sessions.json`
2. Applies retention policy based on type and last activity
3. Moves expired sessions to `archive/YYYY-MM-DD/`
4. Cleans archives older than 30 days
5. Reports detailed breakdown of what was kept/archived

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
  --message "Run: bash ~/.openclaw/skills/openclaw-optimization/scripts/session-cleanup.sh && bash ~/.openclaw/skills/openclaw-optimization/scripts/token-tracker.sh. Post before/after stats summary." \
  --announce

# Daily token tracking
openclaw cron add \
  --name "daily-token-tracking" \
  --cron "0 6 * * *" \
  --tz "America/Edmonton" \
  --agent main \
  --session isolated \
  --timeout-seconds 60 \
  --message "Run: bash ~/.openclaw/skills/openclaw-optimization/scripts/token-tracker.sh"
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

### Multi-Agent Discord Configuration (Bot-to-Bot)

By default, OpenClaw drops messages originating from Discord bots. To enable agents to communicate directly in shared channels:

**Step 1 — Enable bot message reception on ALL agents:**
```json
// openclaw.json → discord plugin
"discord": {
  "allowBots": true,
  ...
}
```

⚠️ **Security:** `allowBots: true` widens the attack surface — any bot in your guild can now trigger the agent. Mitigate with `groupPolicy: "allowlist"` and explicit channel allowlists. Backup configs before changing.

**Step 2 — Disable streaming on all agents:**
```json
"discord": {
  "blockStreaming": true,
  ...
}
```

OpenClaw streams responses by editing a Discord message incrementally. This fires both `MESSAGE_CREATE` (stub) and multiple `MESSAGE_UPDATE` events. Other agents with `allowBots: true` trigger on the partial stub and interpret mid-stream edits as cut-off messages. `blockStreaming: true` posts the complete response at once — one `MESSAGE_CREATE`, no edits, no false triggers. Trade-off: human observers don't see real-time typing preview.

**Step 3 — Configure `requireMention` per channel:**

`requireMention` can be set per-channel (not just globally) in the `groups` object:

```json
"groups": {
  "CHANNEL_ID": {
    "requireMention": false  // respond to all messages in this channel
  },
  "COORDINATION_CHANNEL_ID": {
    "requireMention": false  // agents respond to all coordination messages
  }
}
```

**WebSocket note:** Silent (auto-approved) device pairing only works for `localhost` connections. Remote agents connecting via WebSocket require interactive pairing approval in the OpenClaw UI. REST API (`/tools/invoke`) is the reliable path for remote agent communication — but it only exposes 4 tools: `session_status`, `sessions_list`, `message`, `web_search`.

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

## Phase 6: Camofox Tab Cleanup

Camofox browser tabs spawned by cron jobs are never automatically closed. They accumulate silently until the REST API returns `429 max-tabs` errors, blocking all future browser work.

### When to Use
- Seeing `429` or "max tabs" errors from Camofox tools
- After running browser-heavy cron jobs
- As a daily/weekly scheduled cleanup

### How to Run

```bash
# Preview (safe)
bash scripts/camofox-cleanup.sh --dry-run

# Actually close stale tabs
bash scripts/camofox-cleanup.sh
```

**What it closes:**
- Tabs whose `listItemId` matches `agent:*:cron:*` (cron-spawned)
- Any tab older than 1 hour

**Add to cron:**
```bash
openclaw cron add \
  --name "camofox-tab-cleanup" \
  --cron "0 */6 * * *" \
  --agent main \
  --session isolated \
  --message "Run: bash ~/.openclaw/skills/openclaw-optimization/scripts/camofox-cleanup.sh"
```

## Phase 7: Workspace Budget Tracking

Every message loads all workspace files. Unchecked growth burns tokens silently.

### How to Run

```bash
bash scripts/workspace-budget.sh
```

Checks: `SOUL.md`, `TOOLS.md`, `MEMORY.md`, `AGENTS.md`, `IDENTITY.md`, `USER.md`, `BRAIN.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`

Logs sizes to `~/.openclaw/workspace-budget.csv` with timestamps and shows growth trend vs. previous run.

**Traffic lights:**
| Status | Threshold | Action |
|--------|-----------|--------|
| 🟢 Green | <15KB per file | All good |
| 🟡 Yellow | 15–25KB per file | Consider trimming |
| 🔴 Red | >25KB per file | Trim immediately |

**Add to cron (weekly audit):**
```bash
openclaw cron add \
  --name "workspace-budget" \
  --cron "0 9 * * 1" \
  --agent main \
  --session isolated \
  --message "Run: bash ~/clawd/skills/openclaw-optimization/scripts/workspace-budget.sh. Post results to #alerts if any file is 🔴."
```

## Phase 8: Subagent Delegation

The #1 cause of context bloat in the main session is inline tool calls. Every tool call adds tokens that never go away.

**Rule: if a task needs >2-3 tool calls, spawn a subagent.**

| Delegate to subagent | Keep inline |
|---------------------|-------------|
| Research (web fetches, URL analysis) | Quick one-shot answers |
| Multi-file edits (read + edit + verify) | Conversational replies |
| Email/inbox scans (multiple gog calls) | Simple config lookups |
| Git operations (clone + inspect + commit) | Single file reads |
| Browser-heavy workflows (snapshots, clicks) | — |

**Why it works:** Subagent does the work, returns a clean summary, and its context dies. Main session receives one message instead of accumulating 10+ tool calls. Target: main session stays under 30K context.

**AGENTS.md rule to add:**
```
If a task requires more than 2-3 tool calls, spawn a subagent.
```

## Phase 9: LCM (Lossless Context Management)

OpenClaw supports automatic context compression via the `@martian-engineering/lossless-claw` plugin. It summarizes older turns into a compact DAG while preserving full retrievability.

### Setup

Install the plugin:
```bash
openclaw plugin install @martian-engineering/lossless-claw
```

Configure in `openclaw.json`:
```json
"plugins": {
  "@martian-engineering/lossless-claw": {
    "enabled": true,
    "freshTailCount": 20,
    "contextThreshold": 0.70
  }
}
```

**Key settings:**
| Setting | Default | Purpose |
|---------|---------|---------|
| `freshTailCount` | 20 | Number of recent turns to keep verbatim (not summarized) |
| `contextThreshold` | 0.70 | Fraction of context window that triggers compaction (0.70 = fires at 70%) |

### How It Helps
- Compaction fires automatically when context hits the threshold
- Old turns are summarized losslessly — full text retrievable via `lcm_expand`
- Main session context stays lean without losing history
- Use `lcm_grep` to search compacted turns by keyword or regex

### Retrieving Compacted Context
```bash
# Search for a topic in compacted history
# (use lcm_grep tool in agent prompt)
lcm_grep "pattern"

# Expand a specific summary
lcm_expand --summaryIds sum_abc123
```

LCM complements session cleanup — cleanup removes dead sessions, LCM compresses live ones.

## Success Metrics
After full optimization:
- [ ] All workspace files under target sizes
- [ ] <100 active sessions per agent
- [ ] Weekly cleanup cron running
- [ ] Daily token tracking logging
- [ ] Context usage <60% at session start
- [ ] Month-over-month cost trending down (or stable)
- [ ] No Camofox 429 max-tabs errors
- [ ] Workspace budget CSV showing stable or declining trend
- [ ] LCM plugin enabled with contextThreshold ≤ 0.75
