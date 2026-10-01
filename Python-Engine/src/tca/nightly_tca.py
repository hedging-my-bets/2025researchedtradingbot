from __future__ import annotations

import json
import math
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from statistics import median

EVENTS = Path("MT5-Platform/MQL5/Files/FXSuite/events.ndjson")
SUCCESS_RETCODES = {10008, 10009, 10010, 10025}

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

def percentile(values, q: float):
    xs = sorted(float(x) for x in values)
    if not xs:
        return 0.0
    if len(xs) == 1:
        return xs[0]
    pos = (len(xs) - 1) * q
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return xs[lo]
    return xs[lo] + (xs[hi] - xs[lo]) * (pos - lo)

def session_from_epoch(ts: int) -> str:
    hour = datetime.fromtimestamp(int(ts), tz=timezone.utc).hour
    if hour < 7:
        return "ASIA"
    if hour < 13:
        return "LONDON"
    if hour < 22:
        return "NEW_YORK"
    return "ROLLOVER"

def execution_summary(rows):
    acks = [r for r in rows if r.get("event") == "broker_ack"]
    grouped = defaultdict(list)
    for r in acks:
        key = (r.get("symbol", "UNKNOWN"), session_from_epoch(r.get("ts", 0)))
        grouped[key].append(r)

    out = {}
    for (symbol, session), rs in grouped.items():
        slips, lats, attempts = [], [], []
        rejects = 0
        for r in rs:
            intended = float(r.get("intended_price") or 0)
            fill = float(r.get("fill_price") or 0)
            if intended and fill:
                slips.append(abs(fill - intended))
            retcode = int(r.get("retcode") or 0)
            if retcode not in SUCCESS_RETCODES:
                rejects += 1
            lats.append(int(r.get("latency_ms") or 0))
            attempts.append(int(r.get("attempt") or 1))
        out[f"{symbol}|{session}"] = {
            "orders": len(rs),
            "reject_rate": rejects / max(1, len(rs)),
            "median_abs_slippage_price": median(slips) if slips else 0.0,
            "p95_abs_slippage_price": percentile(slips, 0.95),
            "median_ack_ms": median(lats) if lats else 0.0,
            "p95_ack_ms": percentile(lats, 0.95),
            "p95_attempt": percentile(attempts, 0.95),
        }
    return out

def close_summary(rows):
    closes = [r for r in rows if r.get("event") == "trade_close"]
    grouped = defaultdict(list)
    for r in closes:
        grouped[r.get("symbol", "UNKNOWN")].append(r)

    out = {}
    for symbol, rs in grouped.items():
        gross = sum(float(r.get("gross_profit") or 0.0) for r in rs)
        commission = sum(float(r.get("commission") or 0.0) for r in rs)
        swap = sum(float(r.get("swap") or 0.0) for r in rs)
        net = sum(float(r.get("net_pnl") or 0.0) for r in rs)
        out[symbol] = {
            "closed_deals": len(rs),
            "gross_profit": gross,
            "commission": commission,
            "swap": swap,
            "net_pnl": net,
            "reported_costs": -(commission + swap),
        }
    return out

def summarize(rows):
    return {
        "execution": execution_summary(rows),
        "closes": close_summary(rows),
    }

if __name__ == "__main__":
    print(json.dumps(summarize(load_events()), indent=2, sort_keys=True))
