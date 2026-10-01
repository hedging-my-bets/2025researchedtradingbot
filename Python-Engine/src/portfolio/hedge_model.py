from __future__ import annotations

from dataclasses import dataclass
import numpy as np

@dataclass(frozen=True)
class HedgeEstimate:
    observations: int
    correlation: float
    beta: float
    hedge_ratio: float
    variance_reduction: float

def estimate_hedge(
    primary_returns,
    hedge_returns,
    *,
    lookback_days: int = 90,
    min_days: int = 60,
    max_ratio: float = 1.0,
) -> HedgeEstimate:
    p = np.asarray(primary_returns, dtype=float)
    h = np.asarray(hedge_returns, dtype=float)
    if p.shape != h.shape:
        raise ValueError("return arrays must have same shape")

    mask = np.isfinite(p) & np.isfinite(h)
    p, h = p[mask], h[mask]
    if p.size > lookback_days:
        p, h = p[-lookback_days:], h[-lookback_days:]
    if p.size < min_days:
        raise ValueError(f"need at least {min_days} daily observations")

    var_h = float(np.var(h, ddof=1))
    var_p = float(np.var(p, ddof=1))
    if var_h <= 1e-15 or var_p <= 1e-15:
        raise ValueError("insufficient return variance")

    covariance = float(np.cov(p, h, ddof=1)[0, 1])
    beta = covariance / var_h
    corr = float(np.corrcoef(p, h)[0, 1])
    hedge_ratio = float(np.clip(-beta, -abs(max_ratio), abs(max_ratio)))

    hedged = p + hedge_ratio * h
    var_hedged = float(np.var(hedged, ddof=1))
    reduction = 1.0 - var_hedged / var_p

    return HedgeEstimate(
        observations=int(p.size),
        correlation=corr,
        beta=beta,
        hedge_ratio=hedge_ratio,
        variance_reduction=float(reduction),
    )
