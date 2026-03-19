#!/bin/bash
# session-archive.sh — Cross-machine session cleanup orchestrator
# Runs session-cleanup.sh on Henri (local), Luna, and Atlas via SSH
# Usage: session-archive.sh [--dry-run] [--local-only]
set -uo pipefail

DRY_RUN=""
LOCAL_ONLY=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="--dry-run" ;;
    --local-only) LOCAL_ONLY=1 ;;
  esac
done

CLEANUP_SCRIPT="skills/openclaw-optimization/scripts/session-cleanup.sh"
WORKSPACE="${CLAWD_WORKSPACE:-$HOME/.openclaw}"
RESULTS=""
TOTAL_FREED=0

log() { echo "[$(date +'%H:%M:%S')] $*"; }

run_local() {
  log "🖥️  Henri (local)"
  local output
  output=$(cd "$WORKSPACE" && bash "$CLEANUP_SCRIPT" main ~/.openclaw/agents $DRY_RUN 2>&1) || true
  echo "$output" | tail -5
  RESULTS+="**Henri:** $(echo "$output" | grep -E '(archived|removed|freed|would)' | head -3 | tr '\n' '; ')\n"
  local freed=$(echo "$output" | grep -oE '[0-9.]+ ?[MG]B freed' | head -1)
  [ -n "$freed" ] && RESULTS+="  Freed: $freed\n"
}

run_remote() {
  local name="$1" user="$2" ip="$3" workspace="$4"
  log "🌐 $name ($ip)"

  if ! ssh -o ConnectTimeout=5 "$user@$ip" "true" 2>/dev/null; then
    log "  ⚠️  $name unreachable, skipping"
    RESULTS+="**$name:** unreachable\n"
    return
  fi

  local remote_script="$workspace/$CLEANUP_SCRIPT"
  local has_script
  has_script=$(ssh "$user@$ip" "[ -f '$remote_script' ] && echo yes || echo no" 2>/dev/null)

  if [ "$has_script" = "no" ]; then
    log "  📦 Syncing cleanup script to $name..."
    ssh "$user@$ip" "mkdir -p '$workspace/skills/openclaw-optimization/scripts/'"
    scp -q "$WORKSPACE/$CLEANUP_SCRIPT" "$user@$ip:$remote_script"
    ssh "$user@$ip" "chmod +x '$remote_script'"
  fi

  local output
  output=$(ssh "$user@$ip" "cd '$workspace' && bash '$remote_script' main ~/.openclaw/agents $DRY_RUN" 2>&1) || true
  echo "$output" | tail -5
  RESULTS+="**$name:** $(echo "$output" | grep -E '(archived|removed|freed|would)' | head -3 | tr '\n' '; ')\n"
}

echo "═══════════════════════════════════════════"
echo "  Session Archive — $(date +'%Y-%m-%d %H:%M %Z')"
[ -n "$DRY_RUN" ] && echo "  MODE: DRY RUN (no changes)"
echo "═══════════════════════════════════════════"
echo ""

run_local

if [ -z "$LOCAL_ONLY" ]; then
  echo ""
  run_remote "Luna" "luna" "192.168.4.212" "/Users/luna/.openclaw"
  echo ""
  run_remote "Atlas" "atlas" "192.168.4.216" "/Users/atlas/.openclaw"
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════"
echo -e "$RESULTS"
