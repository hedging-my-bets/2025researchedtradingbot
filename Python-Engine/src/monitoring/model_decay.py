from collections import deque
import numpy as np

class ModelDecayMonitor:
    """
    Tracks live calibration & performance drift; triggers retrain when thresholds violated.
    """
    def __init__(self, window=2000, auc_floor=0.55, ece_ceiling=0.08):
        self.y_true = deque(maxlen=window)
        self.y_prob = deque(maxlen=window)
        self.auc_floor = auc_floor
        self.ece_ceiling = ece_ceiling

    def update(self, y_true: int, y_prob: float):
        self.y_true.append(int(y_true)); self.y_prob.append(float(y_prob))

    def should_retrain(self) -> bool:
        if len(self.y_true) < 200: return False
        y = np.array(self.y_true); p = np.array(self.y_prob)
        # Tiny AUC proxy (Mann–Whitney U)
        auc = (np.sum(p[y==1][:,None] > p[y==0][None,:]) / (np.sum(y==1)*np.sum(y==0)+1e-9))
        # ECE (naive)
        bins = np.linspace(0,1,11); idx = np.digitize(p, bins)-1
        ece = 0.0
        for b in range(10):
            sel = (idx==b);
            if sel.any(): ece += abs(p[sel].mean() - y[sel].mean()) * (sel.mean())
        return (auc < self.auc_floor) or (ece > self.ece_ceiling)