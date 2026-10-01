from __future__ import annotations
from dataclasses import dataclass
from hashlib import sha256
from typing import Iterable

@dataclass(frozen=True)
class ExecutionBucket:
    symbol: str
    session: str
    spread_bucket: str
    vol_bucket: str

@dataclass(frozen=True)
class ExecutionModel:
    median_slippage_points: float
    reject_rate: float
    ack_ms_median: float

def stable_unit(seed_text: str) -> float:
    h = sha256(seed_text.encode()).digest()
    return int.from_bytes(h[:8], "big") / float(2**64 - 1)

def simulate_order(bucket: ExecutionBucket, model: ExecutionModel, correlation_id: str) -> dict:
    u = stable_unit("|".join([bucket.symbol, bucket.session, bucket.spread_bucket, bucket.vol_bucket, correlation_id]))
    rejected = u < max(0.0, min(1.0, model.reject_rate))
    # deterministic symmetric variation around the observed median
    variation = (stable_unit(correlation_id + ":slip") - 0.5) * 0.5
    slippage_points = max(0.0, model.median_slippage_points * (1.0 + variation))
    return {
        "rejected": rejected,
        "slippage_points": slippage_points,
        "ack_ms": max(0.0, model.ack_ms_median * (0.75 + stable_unit(correlation_id + ":ack") * 0.5)),
    }

def parity_error_pct(simulated: Iterable[float], live: Iterable[float]) -> float:
    s = list(simulated)
    l = list(live)
    if not s or not l:
        raise ValueError("need both simulated and live observations")
    s_med = sorted(s)[len(s)//2]
    l_med = sorted(l)[len(l)//2]
    return abs(s_med - l_med) / max(abs(l_med), 1e-12)
