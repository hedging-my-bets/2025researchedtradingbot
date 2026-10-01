from __future__ import annotations
import json
from collections import defaultdict
from pathlib import Path
from statistics import median

EVENTS = Path("MT5-Platform/MQL5/Files/FXSuite/events.ndjson")

def load_events(path: Path = EVENTS):
    if not path.exists():
        return []
    rows = []
    for line in path.read_text(errors="ignore").splitlines():
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows

def summarize(rows):
    acks = [r for r in rows if r.get("event") == "broker_ack"]
    grouped = defaultdict(list)
    for r in acks:
        grouped[r.get("symbol", "UNKNOWN")].append(r)

    out = {}
    for sym, rs in grouped.items():
        slips = []
        rejects = 0
        lats = []
        for r in rs:
            intended = float(r.get("intended_price") or 0)
            fill = float(r.get("fill_price") or 0)
            if intended and fill:
                slips.append(abs(fill - intended))
            if int(r.get("retcode") or 0) not in (10008, 10009, 10010, 10025):
                rejects += 1
            lats.append(int(r.get("latency_ms") or 0))
        out[sym] = {
            "orders": len(rs),
            "reject_rate": rejects / max(1, len(rs)),
            "median_abs_slippage_price": median(slips) if slips else 0.0,
            "median_ack_ms": median(lats) if lats else 0.0,
        }
    return out

if __name__ == "__main__":
    print(json.dumps(summarize(load_events()), indent=2))
