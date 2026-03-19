#!/usr/bin/env python3
"""model-budget-watchdog.py — Track per-model API spend and flag budget overruns.

Usage:
    python3 model-budget-watchdog.py --ingest          # Scan today's sessions
    python3 model-budget-watchdog.py --report           # Show spend report
    python3 model-budget-watchdog.py --alert 5.00       # Custom threshold (default $5)
    python3 model-budget-watchdog.py --reset             # Clear tracking data
"""
import json, os, sys, glob
from datetime import datetime, date
from pathlib import Path
from collections import defaultdict

DATA_DIR = Path.home() / ".openclaw"
TRACKING_FILE = DATA_DIR / "budget-tracking.json"
SESSION_DIR = DATA_DIR / "agents"

# USD per 1M tokens: (input, output)
PRICING = {
    # GitHub Copilot  
    "github-copilot/claude-haiku-4.5": (0.25,1.25),
    "github-copilot/claude-opus-4.5": (5.0,25.0),
    "github-copilot/claude-opus-4.6": (5.0,25.0),
    "github-copilot/claude-sonnet-4": (3.0,15.0),
    "github-copilot/claude-sonnet-4.5": (5.0,25.0),
    "github-copilot/claude-sonnet-4.6": (5.0,25.0),

    "github-copilot/gemini-2.5-pro": (1.0,10.0),
    "github-copilot/gemini-3-flash-preview": (0.5,3),  
    "github-copilot/gemini-3-pro-preview": (2,12),
    "github-copilot/gemini-3.1-pro-preview": (2,12),

    "github-copilot/gpt-4.1": (2,8),
    "github-copilot/gpt-4o": (2.5,10.0),

    "github-copilot/gpt-5": (1.25,10.0),
    "github-copilot/gpt-5-mini": (0.25,2),

    "github-copilot/gpt-5.1": (1.25,10),
    "github-copilot/gpt-5.1-codex": (1.25,10.0),
    "github-copilot/gpt-5.1-codex-max": (1.25,10.0),
    "github-copilot/gpt-5.1-codex-mini": (0.25,2),

    "github-copilot/gpt-5.2": (1.75,14.0),
    "github-copilot/gpt-5.2-codex": (1.75,14.0),
    "github-copilot/gpt-5.3-codex": (1.75,14.0),

    "github-copilot/gpt-5.4": (2.5,15),	

    "github-copilot/grok-code-fast-1": (0.2,1.5),
    
    # Anthropic — Max subscription (OAuth), not API-billed
    "anthropic/claude-opus-4-6": (0, 0),
    "claude-opus-4-6": (0, 0),
    "anthropic/claude-sonnet-4-6": (0, 0),
    "claude-sonnet-4-6": (0, 0),
    # OpenAI Codex (subscription — $0)
    "openai-codex/gpt-5.4": (0, 0),
    "gpt-5.4": (0, 0),
    # OpenRouter
    "openrouter/minimax/minimax-m2.5": (0.27, 1.10),
    "minimax-m2.5": (0.27, 1.10),
    "openrouter/google/gemini-3.1-pro": (1.25, 10.0),
    "gemini-3.1-pro": (1.25, 10.0),
    # Local (free)
    "local-glm/glm-4.7-flash": (0, 0),
    "glm-4.7-flash": (0, 0),
    "local-qwen/qwen3.5-35b-a3b": (0, 0),
    "qwen3.5-35b-a3b": (0, 0),
    # Meta
    "delivery-mirror": (0, 0),
}

def load_tracking():
    if TRACKING_FILE.exists():
        return json.loads(TRACKING_FILE.read_text())
    return {"daily": {}, "models": {}, "alerts": []}

def save_tracking(data):
    # Keep only last 30 days
    dates = sorted(data["daily"].keys())
    for d in dates[:-30]:
        del data["daily"][d]
    TRACKING_FILE.write_text(json.dumps(data, indent=2))

def cost(model, inp, out):
    in_p, out_p = PRICING.get(model, (0, 0))
    return (inp * in_p + out * out_p) / 1_000_000

def ingest(today_str):
    totals = defaultdict(lambda: [0, 0])  # model -> [input, output]
    
    for jsonl_path in SESSION_DIR.rglob("*.jsonl"):
        # Skip files not modified in last 2 days
        try:
            mtime = datetime.fromtimestamp(jsonl_path.stat().st_mtime).date()
            if (date.today() - mtime).days > 1:
                continue
        except:
            continue
        
        try:
            with open(jsonl_path) as f:
                for line in f:
                    try:
                        msg = json.loads(line)
                        ts = (msg.get("timestamp", "") or msg.get("message", {}).get("timestamp", ""))[:10]
                        if ts != today_str:
                            continue
                        # OpenClaw nests under msg.message
                        inner = msg.get("message", msg)
                        model = inner.get("model", msg.get("model", ""))
                        usage = inner.get("usage", msg.get("usage", {}))
                        if not model or not usage:
                            continue
                        inp = usage.get("input", usage.get("input_tokens", usage.get("prompt_tokens", 0))) or 0
                        out = usage.get("output", usage.get("output_tokens", usage.get("completion_tokens", 0))) or 0
                        totals[model][0] += inp
                        totals[model][1] += out
                    except:
                        pass
        except:
            pass
    
    tracking = load_tracking()
    tracking["daily"][today_str] = {}
    for model, (inp, out) in totals.items():
        tracking["daily"][today_str][model] = {"input": inp, "output": out}
        if model not in tracking["models"]:
            tracking["models"][model] = {"total_input": 0, "total_output": 0}
        tracking["models"][model]["total_input"] += inp
        tracking["models"][model]["total_output"] += out
    
    save_tracking(tracking)
    print(f"📊 Ingested {len(totals)} models for {today_str}")
    for model, (inp, out) in sorted(totals.items()):
        c = cost(model, inp, out)
        print(f"  {model}: {inp:,} in / {out:,} out (${c:.4f})")

def report(today_str, threshold):
    tracking = load_tracking()
    today_data = tracking.get("daily", {}).get(today_str, {})
    
    print("═══════════════════════════════════════════")
    print(f"  Model Budget Report — {today_str}")
    print(f"  Alert threshold: ${threshold:.2f}/day")
    print("═══════════════════════════════════════════")
    print()
    
    if not today_data:
        print("  No data for today. Run with --ingest first.")
        print("═══════════════════════════════════════════")
        return
    
    print(f"  {'Model':<40} {'Input':>10} {'Output':>10} {'Cost':>10}")
    print(f"  {'─'*40} {'─'*10} {'─'*10} {'─'*10}")
    
    total_cost = 0
    for model in sorted(today_data):
        usage = today_data[model]
        inp, out = usage["input"], usage["output"]
        c = cost(model, inp, out)
        total_cost += c
        flag = " 🔴" if c > threshold else ""
        print(f"  {model:<40} {inp:>10,} {out:>10,} ${c:>8.4f}{flag}")
    
    print(f"  {'─'*40} {'─'*10} {'─'*10} {'─'*10}")
    print(f"  {'TOTAL':<40} {'':>10} {'':>10} ${total_cost:>8.4f}")
    
    if total_cost > threshold:
        print(f"\n  🚨 OVER BUDGET — ${total_cost:.2f} exceeds ${threshold:.2f} threshold")
    else:
        print(f"\n  ✅ Within budget (${total_cost:.2f} / ${threshold:.2f})")
    
    # 7-day trend
    daily = tracking.get("daily", {})
    dates = sorted(daily.keys())[-7:]
    if len(dates) > 1:
        print(f"\n  📈 7-Day Trend:")
        for d in dates:
            day_cost = sum(cost(m, u["input"], u["output"]) for m, u in daily[d].items())
            bar = "█" * min(int(day_cost * 10), 50)
            print(f"    {d}: ${day_cost:.2f} {bar}")
    
    print()
    print("═══════════════════════════════════════════")

def main():
    today_str = date.today().isoformat()
    threshold = 5.00
    mode = "report"
    
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--ingest":
            mode = "ingest"
        elif args[i] == "--report":
            mode = "report"
        elif args[i] == "--reset":
            mode = "reset"
        elif args[i] == "--alert" and i + 1 < len(args):
            threshold = float(args[i + 1])
            i += 1
        i += 1
    
    if mode == "ingest":
        ingest(today_str)
    elif mode == "report":
        report(today_str, threshold)
    elif mode == "reset":
        save_tracking({"daily": {}, "models": {}, "alerts": []})
        print("✅ Budget tracking reset.")

if __name__ == "__main__":
    main()
