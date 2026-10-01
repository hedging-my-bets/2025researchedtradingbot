from __future__ import annotations
from dataclasses import dataclass, asdict

@dataclass(frozen=True)
class PromotionMetrics:
    rolling_weeks: int
    psr_candidate: float
    psr_baseline: float
    regimes_with_required_lift: int
    ece: float
    brier: float
    conformal_coverage: float
    conformal_width: float
    conformal_max_width: float
    inference_p95_ms: float
    broker_ack_p95_ms: float
    reject_rate: float
    parity_median_error_pct: float
    max_day_dd: float
    max_week_dd: float
    max_peak_dd: float

@dataclass(frozen=True)
class PromotionDecision:
    eligible: bool
    checks: dict
    metrics: dict

def evaluate_promotion(m: PromotionMetrics) -> PromotionDecision:
    checks = {
        "six_rolling_weeks": m.rolling_weeks >= 6,
        # "baseline +15%" is interpreted as +0.15 absolute PSR probability.
        "psr_lift": m.psr_candidate >= m.psr_baseline + 0.15,
        "regime_breadth": m.regimes_with_required_lift >= 3,
        "ece": m.ece <= 0.03,
        "brier": m.brier <= 0.18,
        "conformal_coverage": m.conformal_coverage >= 0.90,
        "conformal_width": m.conformal_width <= m.conformal_max_width,
        "inference_latency": m.inference_p95_ms <= 400.0,
        "broker_ack_latency": m.broker_ack_p95_ms <= 250.0,
        "reject_rate": m.reject_rate <= 0.01,
        "sim_live_parity": m.parity_median_error_pct <= 0.10,
        "daily_drawdown": m.max_day_dd <= 0.03,
        "weekly_drawdown": m.max_week_dd <= 0.07,
        "peak_drawdown": m.max_peak_dd <= 0.12,
    }
    return PromotionDecision(
        eligible=all(checks.values()),
        checks=checks,
        metrics=asdict(m),
    )
