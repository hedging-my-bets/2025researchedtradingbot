import numpy as np
import pandas as pd
from typing import Dict

class FeatureDriftDetector:
    def __init__(self, baseline_samples: Dict[str, np.ndarray], psi_retrain=0.20):
        self.baseline = baseline_samples
        self.psi_retrain = psi_retrain

    @staticmethod
    def psi(expected: np.ndarray, actual: np.ndarray, bins: int = 10) -> float:
        expected = np.asarray(expected, dtype=float)
        actual = np.asarray(actual, dtype=float)
        expected = expected[np.isfinite(expected)]
        actual = actual[np.isfinite(actual)]
        if expected.size < 100 or actual.size < 100:
            return 0.0
        q = np.unique(np.quantile(expected, np.linspace(0.0, 1.0, bins + 1)))
        if q.size < 3:
            return 0.0
        e, _ = np.histogram(expected, bins=q)
        a, _ = np.histogram(actual, bins=q)
        e = np.maximum(e / max(1, e.sum()), 1e-6)
        a = np.maximum(a / max(1, a.sum()), 1e-6)
        return float(np.sum((a - e) * np.log(a / e)))

    def check(self, live: pd.DataFrame) -> Dict[str, float]:
        out: Dict[str, float] = {}
        for col, baseline in self.baseline.items():
            if col not in live:
                continue
            score = self.psi(baseline, live[col].to_numpy()[-8192:])
            if score > self.psi_retrain:
                out[col] = score
        return out

class PageHinkley:
    def __init__(self, delta=0.005, threshold=50.0, alpha=0.999):
        self.delta = delta
        self.threshold = threshold
        self.alpha = alpha
        self.mean = 0.0
        self.cum = 0.0
        self.min_cum = 0.0
        self.n = 0

    def update(self, x: float) -> bool:
        self.n += 1
        self.mean += (x - self.mean) / self.n
        self.cum = self.alpha * self.cum + x - self.mean - self.delta
        self.min_cum = min(self.min_cum, self.cum)
        return (self.cum - self.min_cum) > self.threshold
