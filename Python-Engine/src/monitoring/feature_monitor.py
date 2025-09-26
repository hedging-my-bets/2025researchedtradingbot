# Production drift detector with PSI + alerts map.
import numpy as np, pandas as pd
from typing import Dict

class FeatureDriftDetector:
    def __init__(self, baseline_stats: Dict[str, Dict[str, float]], psi_warn=0.1, psi_crit=0.25):
        self.baseline = baseline_stats
        self.psi_warn = psi_warn
        self.psi_crit = psi_crit

    @staticmethod
    def _psi(expected: np.ndarray, actual: np.ndarray, bins: int = 10) -> float:
        e_hist, b = np.histogram(expected, bins=bins)
        a_hist, _ = np.histogram(actual, bins=b)
        e = e_hist / (e_hist.sum() + 1e-12)
        a = a_hist / (a_hist.sum() + 1e-12)
        return float(np.sum((a - e) * np.log((a + 1e-12) / (e + 1e-12))))

    def check(self, live: pd.DataFrame) -> Dict[str, str]:
        alerts: Dict[str,str] = {}
        for col, stats in self.baseline.items():
            if col not in live.columns: continue
            e = np.random.normal(stats.get("mean",0.0), max(1e-6, stats.get("std",1.0)), size=8192)
            a = live[col].dropna().values[-8192:]
            if a.size < 100: continue
            score = self._psi(e, a)
            if score > self.psi_crit: alerts[col] = "CRITICAL"
            elif score > self.psi_warn: alerts[col] = "WARNING"
        return alerts