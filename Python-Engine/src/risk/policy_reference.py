from __future__ import annotations

def final_size_multiplier(*caps: float) -> float:
    if not caps:
        return 1.0
    return max(0.0, min(1.0, min(float(x) for x in caps)))

def drawdown_state(
    day_dd: float,
    week_dd: float,
    peak_dd: float,
    *,
    day_limit: float = 0.03,
    week_limit: float = 0.07,
    peak_limit: float = 0.12,
    soft_fraction: float = 0.70,
) -> tuple[str, float]:
    if day_dd >= day_limit or week_dd >= week_limit or peak_dd >= peak_limit:
        return "HARD_HALT", 0.0
    if (
        day_dd >= day_limit * soft_fraction
        or week_dd >= week_limit * soft_fraction
        or peak_dd >= peak_limit * soft_fraction
    ):
        return "SOFT_HALT", 0.5
    return "NORMAL", 1.0
