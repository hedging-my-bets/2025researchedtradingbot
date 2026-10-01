from collections import deque
import numpy as np

class ModelDecayMonitor:
    def __init__(self, window=2000, ece_ceiling=0.03, brier_ceiling=0.18, mce_ceiling=0.10):
        self.y_true = deque(maxlen=window)
        self.y_prob = deque(maxlen=window)
        self.ece_ceiling = ece_ceiling
        self.brier_ceiling = brier_ceiling
        self.mce_ceiling = mce_ceiling

    def update(self, y_true: int, y_prob: float) -> None:
        self.y_true.append(int(y_true))
        self.y_prob.append(float(np.clip(y_prob, 0.0, 1.0)))

    @staticmethod
    def metrics(y: np.ndarray, p: np.ndarray) -> dict:
        brier = float(np.mean((p - y) ** 2))
        edges = np.linspace(0.0, 1.0, 11)
        idx = np.clip(np.digitize(p, edges) - 1, 0, 9)
        ece, mce = 0.0, 0.0
        for b in range(10):
            sel = idx == b
            if not sel.any():
                continue
            gap = abs(float(p[sel].mean()) - float(y[sel].mean()))
            ece += gap * float(sel.mean())
            mce = max(mce, gap)
        return {"ece": ece, "brier": brier, "mce": mce}

    def should_retrain(self) -> bool:
        if len(self.y_true) < 200:
            return False
        y = np.asarray(self.y_true, dtype=float)
        p = np.asarray(self.y_prob, dtype=float)
        m = self.metrics(y, p)
        return (
            m["ece"] > self.ece_ceiling
            or m["brier"] > self.brier_ceiling
            or m["mce"] > self.mce_ceiling
        )
