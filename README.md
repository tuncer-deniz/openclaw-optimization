# 🚀 OpenClaw Optimization Skill

Systematic performance optimization for [OpenClaw](https://github.com/openclaw/openclaw) AI agents. Reduce token usage, clean up session bloat, and automate ongoing maintenance.

## The Problem

OpenClaw agents accumulate cruft over time:
- **Orphaned sessions** from sub-agents and cron jobs pile up (we found 1,036 orphans totaling 75MB on one machine)
- **Bloated workspace files** (MEMORY.md, TOOLS.md) grow unchecked, eating context budget every message
- **No visibility** into token usage trends or context budget allocation

This skill fixes all of it.

## What You Get

| Tool | Purpose |
|------|---------|
| `health-check.sh` | Quick traffic-light assessment of your setup |
| `session-cleanup.sh` | Archive orphaned and stale sessions |
| `token-tracker.sh` | Log per-agent usage metrics over time |
| `find-orphans.py` | Identify unreferenced session files |
| `fix-sessions-json.py` | Repair sessions.json pointing to missing files |
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
# Weekly session cleanup (Sundays 3 AM)
openclaw cron add \
  --name "weekly-session-cleanup" \
  --cron "0 3 * * 0" \
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

## Results

From our production multi-agent setup (3 agents, 5 sub-agents):

| Metric | Before | After |
|--------|--------|-------|
| Sessions (main) | 1,102 | 65 |
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

- OpenClaw 2026.2.x
- Python 3.10+
- bash

## License

MIT

## Contributing

Found a new bloat pattern? Session type that should be auto-archived? Open a PR.
