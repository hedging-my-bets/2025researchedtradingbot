from __future__ import annotations

from collections import defaultdict
from dataclasses import asdict
from statistics import median

from execution.execution_simulator import ExecutionBucket, ExecutionModel
from tca.nightly_tca import SUCCESS_RETCODES, session_from_epoch

def bucket_key(row: dict) -> ExecutionBucket:
    return ExecutionBucket(
        symbol=str(row.get("symbol", "UNKNOWN")),
        session=str(row.get("session") or session_from_epoch(row.get("ts", 0))),
        spread_bucket=str(row.get("spread_bucket", "UNKNOWN")),
        vol_bucket=str(row.get("vol_bucket", "UNKNOWN")),
    )

def fit_execution_models(rows: list[dict]) -> dict[str, dict]:
    grouped = defaultdict(list)
    for row in rows:
        if row.get("event") == "broker_ack":
            grouped[bucket_key(row)].append(row)

    out = {}
    for bucket, rs in grouped.items():
        slips = []
        acks = []
        rejects = 0
        for r in rs:
            intended = float(r.get("intended_price") or 0.0)
            fill = float(r.get("fill_price") or 0.0)
            if intended and fill:
                slips.append(abs(fill - intended))
            acks.append(float(r.get("latency_ms") or 0.0))
            if int(r.get("retcode") or 0) not in SUCCESS_RETCODES:
                rejects += 1
        model = ExecutionModel(
            median_slippage_points=float(median(slips)) if slips else 0.0,
            reject_rate=rejects / max(1, len(rs)),
            ack_ms_median=float(median(acks)) if acks else 0.0,
        )
        key = "|".join([bucket.symbol,bucket.session,bucket.spread_bucket,bucket.vol_bucket])
        out[key] = asdict(model)
    return out

def parity_report(modeled: dict[str, float], live: dict[str, float]) -> dict:
    keys = sorted(set(modeled) & set(live))
    buckets = {}
    for key in keys:
        m = float(modeled[key])
        l = float(live[key])
        err = abs(m - l) / max(abs(l), 1e-12)
        buckets[key] = {"modeled": m, "live": l, "error_pct": err, "within_10pct": err <= 0.10}
    return {
        "buckets": buckets,
        "all_within_10pct": bool(buckets) and all(x["within_10pct"] for x in buckets.values()),
    }
