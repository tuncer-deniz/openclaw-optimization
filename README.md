# 🚀 OpenClaw Optimization Skill v4.0.0

Systematic performance optimization for [OpenClaw](https://github.com/openclaw/openclaw) AI agents. Reduce token usage, clean up session bloat, and automate ongoing maintenance.

## What's New in v4

**Camofox tab cleanup** — Cron jobs spawn Camofox browser tabs and never close them. They pile up silently until you hit `429 max-tabs` errors. `camofox-cleanup.sh` uses the Camofox REST API to close cron-spawned tabs (matched by `agent:*:cron:*` listItemId) and any tab older than 1 hour. Supports `--dry-run`.

**Workspace budget tracking** — `workspace-budget.sh` measures all workspace context files (SOUL.md, TOOLS.md, MEMORY.md, etc.) and logs sizes to `~/.openclaw/workspace-budget.csv` with timestamps. Traffic-light output (🟢/🟡/🔴) at 15KB warn / 25KB critical, plus growth trend vs. last run.

**Subagent delegation guidance** — SKILL.md now includes a delegation threshold rule: if a task needs >2-3 tool calls, spawn a subagent. Every inline tool call adds tokens that never go away. Subagents do the work, return a clean result, and their context dies. Main session target: stay under 30K context.

**LCM integration notes** — The `@martian-engineering/lossless-claw` plugin compresses old conversation turns into a lossless DAG. SKILL.md covers install, key settings (`freshTailCount`, `contextThreshold`), and how to retrieve compacted context via `lcm_grep` / `lcm_expand`.

## What's New in v3

**Orphaned temp file cleanup** — OpenClaw's atomic session writes leave behind `sessions.json.*.tmp` files that never get cleaned up. We found **23GB of these on one machine** and 2.9GB on another. v3 detects and removes them before they cause Node.js OOM crashes during `openclaw doctor` or `openclaw update`.

**sessions.json pruning** — Removes entries pointing to nonexistent session files. One machine had 15,302 orphan entries inflating sessions.json to 289MB.

**Smart retention policy (v2)** — Sessions classified by type with appropriate retention:

| Session Type | Retention | Rationale |
|--------------|-----------|-----------|
| Persistent channels (#discord, telegram) | Forever | Compaction handles size |
| Completed sub-agents | 24 hours | Debugging window only |
| Cron job sessions | 24 hours | Each run is isolated |
| Stale sessions | 48 hours | If untouched, it's dead |
| Large stale (>5MB) | 7 days | Extra buffer |

**Dry-run mode** — Preview what would be archived before committing:
```bash
bash scripts/session-cleanup.sh main ~/.openclaw/agents --dry-run
```

## The Problem

OpenClaw agents accumulate cruft over time:
- **Orphaned `.tmp` files** from atomic writes silently consume disk — we found 23GB on one machine, causing Node.js OOM crashes
- **Orphaned session entries** in sessions.json pointing to deleted files (15,302 entries / 289MB on one machine)
- **Orphaned sessions** from sub-agents and cron jobs pile up (1,036 orphans totaling 75MB on one machine)
- **Bloated workspace files** (MEMORY.md, TOOLS.md) grow unchecked, eating context budget every message
- **No visibility** into token usage trends or context budget allocation

This skill fixes all of it.

## What You Get

| Tool | Purpose |
|------|---------|
| `health-check.sh` | Quick traffic-light assessment of your setup |
| `session-cleanup.sh` | Smart retention-based session archival (v2) |
| `token-tracker.sh` | Log per-agent usage metrics over time |
| `find-orphans.py` | Identify unreferenced session files |
| `fix-sessions-json.py` | Repair sessions.json pointing to missing files |
| `checkpoint.sh` | Auto-checkpoint session state before subagent spawns |
| `session-archive.sh` | Cross-machine session cleanup orchestrator (SSH) |
| `camofox-cleanup.sh` | Close orphaned Camofox tabs left by cron jobs (429 prevention) |
| `workspace-budget.sh` | Track workspace file sizes with trend analysis and alerts |
| `SKILL.md` | Full optimization playbook for agents |

## Quick Start

```bash
# Clone into your skills directory
git clone https://github.com/tuncer-deniz/openclaw-optimization.git \
  ~/.openclaw/skills/openclaw-optimization

# Or copy to your workspace
cp -r openclaw-optimization ~/clawd/skills/

# Run health check
cd skills/openclaw-optimization
bash scripts/health-check.sh

# Clean up sessions
bash scripts/session-cleanup.sh main

# Start tracking
bash scripts/token-tracker.sh
```

## Health Check Output

```
═══════════════════════════════════════════
  OpenClaw Health Check — 2026-02-19 18:46
═══════════════════════════════════════════

📦 SESSION STATUS
─────────────────
  🔴 main: 1102 sessions, 132.0MB
  🟢 scout: 7 sessions, 2.5MB
  🟢 dispatch: 7 sessions, 0.6MB

👻 ORPHAN CHECK
─────────────────
  🔴 main: 1036 orphaned (of 1102)

📄 CONTEXT BUDGET (workspace files)
─────────────────
  SOUL.md: 1.8KB
  TOOLS.md: 3.2KB
  MEMORY.md: 5.7KB
  🟢 Total: 20.1KB
```

## Automation

Set up cron jobs for hands-off maintenance:

```bash
# Daily session cleanup (4 AM) — recommended with v2 retention policy
openclaw cron add \
  --name "daily-session-cleanup" \
  --cron "0 4 * * *" \
  --agent main \
  --session isolated \
  --message "Run: bash ~/clawd/skills/openclaw-optimization/scripts/session-cleanup.sh"

# Daily token tracking (6 AM)
openclaw cron add \
  --name "daily-token-tracking" \
  --cron "0 6 * * *" \
  --agent main \
  --session isolated \
  --message "Run: bash ~/clawd/skills/openclaw-optimization/scripts/token-tracker.sh"
```

With the 24h/48h retention windows in v2, **daily cleanup is recommended** over weekly.

## Session Archive (Fleet-Wide Cleanup)

Run session-cleanup.sh across all machines in one command:

```bash
# Preview (no changes)
bash scripts/session-archive.sh --dry-run

# Clean all machines
bash scripts/session-archive.sh

# Local only (skip SSH)
bash scripts/session-archive.sh --local-only
```

Connects to Henri (local), Luna, and Atlas via SSH. Auto-syncs the cleanup script to remote machines if missing. Set up as a weekly cron for hands-off fleet maintenance.

## Model Budget Watchdog

Track per-model API spend, flag budget overruns, and show 7-day trends:

```bash
# Ingest today's usage from session JSONL files
python3 scripts/model-budget-watchdog.py --ingest

# Show report (default $5/day threshold)
python3 scripts/model-budget-watchdog.py --report

# Custom threshold
python3 scripts/model-budget-watchdog.py --report --alert 10.00

# Reset tracking
python3 scripts/model-budget-watchdog.py --reset
```

Pricing is built-in for Anthropic, OpenRouter, and local models. Add new models to the `PRICING` dict. Subscription models (Codex gpt-5.4) and local models are $0.

## Channel Health

Verify multi-agent Discord channel visibility — gateway health + channel config across all machines:

```bash
# Check gateway status + channel config
bash scripts/channel-health.sh

# Override which channels to check
CHANNEL_HEALTH_CHANNELS="coordination:123 orders:456" bash scripts/channel-health.sh
```

Edit the `SHARED_CHANNELS` array in the script to match your guild's channel IDs.

## Checkpoint on Spawn

Prevents "continue where you left off" recovery loops after compaction or timeouts. Write a structured checkpoint before spawning subagents:

```bash
bash scripts/checkpoint.sh \
  "Building new feature X" \
  "User asked for X, I proposed approach Y" \
  "Waiting on CI results" \
  "src/app/feature.tsx, AGENTS.md" \
  "focused"
```

Writes to both `memory/session-state.md` (overwrite) and `memory/YYYY-MM-DD.md` (append). After compaction, agents read these files first to seamlessly resume.

Add this rule to your AGENTS.md:
```
Before ANY sessions_spawn call or long-running exec (>2 min), write a checkpoint FIRST.
```

## Results

From our production multi-agent setup (3 agents, 5 sub-agents):

| Metric | Before | After |
|--------|--------|-------|
| Disk (tmp files) | 23GB | 0 |
| Sessions (main) | 1,102 | 65 |
| sessions.json | 289MB | 93KB |
| Session storage | 132MB | 28MB |
| MEMORY.md | 12.8KB | 5.9KB |
| Workspace total | ~35KB | 20KB |
| Context at boot | ~75% | ~56% |

## Context Budget Guidelines

Every message loads all workspace files. Keep them lean:

| File | Target | What belongs |
|------|--------|-------------|
| SOUL.md | <2KB | Personality, tone, rules |
| TOOLS.md | <4KB | Active tool configs only |
| MEMORY.md | <6KB | Current state, active projects |
| AGENTS.md | <4KB | Routing rules, channels |
| IDENTITY.md | <500B | Name, emoji, one-liner |

## Multi-Agent

Each agent maintains its own sessions. For fleet-wide cleanup:

```bash
# Run on each agent's machine
for agent in main scout dispatch sentinel; do
  bash scripts/session-cleanup.sh "$agent"
done
```

For remote agents via LAN API, the SKILL.md includes curl templates.

## Requirements

- OpenClaw 2026.2.x+
- Python 3.10+
- bash

## License

MIT

## Contributing

Found a new bloat pattern? Session type that should be auto-archived? Open a PR.
