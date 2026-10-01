from __future__ import annotations
import math
import numpy as np

def probabilistic_sharpe_ratio(
    returns,
    benchmark_sharpe: float = 0.0,
) -> float:
    r = np.asarray(returns, dtype=float)
    r = r[np.isfinite(r)]
    n = r.size
    if n < 3:
        return 0.0
    std = float(r.std(ddof=1))
    if std <= 0.0:
        return 0.0
    sr = float(r.mean() / std)
    centered = r - r.mean()
    m2 = float(np.mean(centered ** 2))
    if m2 <= 0.0:
        return 0.0
    skew = float(np.mean(centered ** 3) / (m2 ** 1.5))
    kurt = float(np.mean(centered ** 4) / (m2 ** 2))
    denom_sq = 1.0 - skew * sr + ((kurt - 1.0) / 4.0) * (sr ** 2)
    if denom_sq <= 1e-12:
        return 0.0
    z = (sr - benchmark_sharpe) * math.sqrt(n - 1.0) / math.sqrt(denom_sq)
    return 0.5 * (1.0 + math.erf(z / math.sqrt(2.0)))
