#!/bin/bash
# channel-health.sh — Verify multi-agent Discord channel visibility
# Checks gateway health + channel config across Henri, Luna, Atlas
# Usage: channel-health.sh [--ping] (--ping sends test messages)
set -o pipefail

PING_TEST=""
[[ "${*:-}" == *"--ping"* ]] && PING_TEST=1

# Agent definitions: name|ip|port|token
AGENT_HENRI="192.168.4.213|18789|local"
AGENT_LUNA="192.168.4.212|18789|oc_gw_4b74f2c3e9a1d5b8"
AGENT_ATLAS="192.168.4.216|18789|29d2c0d343354139051bc6ff94b9202fe08f7d99fa564f39"
AGENT_LIST="henri luna atlas"

# Key shared channels that all agents should see
# Edit these to match your Discord guild's channel IDs
# Format: "friendly-name:channel-id"
SHARED_CHANNELS=(
  "coordination:1471311969788448923"
  "orders:1471312034380812379"
  "team-memory:1471312120506695780"
)
# Override via env: CHANNEL_HEALTH_CHANNELS="name1:id1 name2:id2"
if [ -n "${CHANNEL_HEALTH_CHANNELS:-}" ]; then
  SHARED_CHANNELS=($CHANNEL_HEALTH_CHANNELS)
fi

OK=0
WARN=0
FAIL=0

log_ok()   { echo "  ✅ $*"; ((OK++)); }
log_warn() { echo "  ⚠️  $*"; ((WARN++)); }
log_fail() { echo "  ❌ $*"; ((FAIL++)); }

echo "═══════════════════════════════════════════"
echo "  Channel Health Check — $(date +'%Y-%m-%d %H:%M %Z')"
echo "═══════════════════════════════════════════"

# Phase 1: Gateway health
echo ""
echo "📡 GATEWAY STATUS"
echo "─────────────────"

for agent in $AGENT_LIST; do
  eval "agent_data=\$AGENT_$(echo $agent | tr '[:lower:]' '[:upper:]')"
  IFS='|' read -r ip port token <<< "$agent_data"
  if [ "$token" = "local" ]; then
    status=$(curl -sf -m 5 "http://localhost:$port/health" 2>/dev/null && echo "ok" || echo "fail")
  else
    status=$(curl -sf -m 5 "http://$ip:$port/health" -H "Authorization: Bearer $token" 2>/dev/null && echo "ok" || echo "fail")
  fi

  if [ "$status" != "fail" ]; then
    log_ok "$agent gateway ($ip:$port) — UP"
  else
    log_fail "$agent gateway ($ip:$port) — DOWN"
  fi
done

# Phase 2: Channel config verification via SSH
echo ""
echo "📋 CHANNEL CONFIG"
echo "─────────────────"

check_channel_config() {
  local agent="$1" ssh_target="$2" config_path="$3"
  
  for entry in "${SHARED_CHANNELS[@]}"; do
    IFS=':' read -r name id <<< "$entry"
    
    local found
    local found
    if [ "$ssh_target" = "local" ]; then
      found=$(grep -l "\"$id\"" "$config_path" >/dev/null 2>&1 && echo "yes" || echo "no")
    else
      found=$(ssh -o ConnectTimeout=5 "$ssh_target" "grep -l '$id' '$config_path' >/dev/null 2>&1 && echo yes || echo no" 2>/dev/null)
    fi

    case "$found" in
      yes) log_ok "$agent can see #$name ($id)" ;;
      no)  log_fail "$agent missing #$name ($id) in config" ;;
      *)   log_warn "$agent config check failed for #$name" ;;
    esac
  done
}

check_channel_config "henri" "local" "$HOME/.openclaw/openclaw.json"
check_channel_config "luna" "luna@192.168.4.212" "/Users/luna/.openclaw/openclaw.json"
check_channel_config "atlas" "atlas@192.168.4.216" "/Users/atlas/.openclaw/openclaw.json"

# Phase 3: Ping test (optional)
if [ -n "$PING_TEST" ]; then
  echo ""
  echo "🏓 PING TEST"
  echo "─────────────────"
  echo "  (Ping test requires running from OpenClaw agent context — use the skill, not this script directly)"
fi

# Summary
echo ""
echo "═══════════════════════════════════════════"
echo "  Results: ✅ $OK passed | ⚠️  $WARN warnings | ❌ $FAIL failures"
echo "═══════════════════════════════════════════"

[ "$FAIL" -gt 0 ] && exit 1
exit 0
