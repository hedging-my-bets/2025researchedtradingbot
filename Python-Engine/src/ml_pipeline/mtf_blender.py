from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import numpy as np

TF_NAMES = ("m15", "h1", "h4", "d1")

def news_bucket(minutes_to_news: float) -> str:
    if minutes_to_news < 30.0:
        return "near"
    if minutes_to_news < 120.0:
        return "mid"
    return "far"

@dataclass(frozen=True)
class MTFResult:
    blend: float
    coherence: float
    threshold_add: float
    blocked: bool
    weights: tuple[float, float, float, float]

class MTFBlender:
    def __init__(self, config: dict):
        self.config = config

    @classmethod
    def load(cls, path: Path):
        return cls(json.loads(path.read_text()))

    def weights(self, regime: int, minutes_to_news: float) -> np.ndarray:
        key = f"{int(regime)}:{news_bucket(minutes_to_news)}"
        raw = self.config.get("groups", {}).get(key, self.config["default_weights"])
        w = np.asarray(raw, dtype=float)
        w = np.clip(w, 0.0, None)
        if w.shape != (4,) or w.sum() <= 0.0:
            raise ValueError("MTF weights must be four non-negative values")
        return w / w.sum()

    def blend(self, probs, regime: int, minutes_to_news: float) -> MTFResult:
        p = np.asarray(probs, dtype=float)
        if p.shape != (4,) or not np.isfinite(p).all():
            raise ValueError("need four finite MTF probabilities")
        p = np.clip(p, 0.0, 1.0)
        w = self.weights(regime, minutes_to_news)
        blend = float(np.dot(w, p))

        base_dir = 1 if p[0] >= 0.5 else -1
        higher_dirs = np.where(p[1:] >= 0.5, 1, -1)
        higher_w = w[1:]
        agreement = float(higher_w[higher_dirs == base_dir].sum())
        coherence = agreement / max(float(higher_w.sum()), 1e-12)

        policy = self.config["policy"]
        block_level = float(policy["coherence_block"])
        warn_level = float(policy["coherence_warn"])
        both_high_tf_opposite = higher_dirs[1] != base_dir and higher_dirs[2] != base_dir

        blocked = coherence < block_level and both_high_tf_opposite
        if coherence < block_level:
            threshold_add = float(policy["threshold_add_block"])
        elif coherence < warn_level:
            threshold_add = float(policy["threshold_add_warn"])
        else:
            threshold_add = 0.0

        return MTFResult(
            blend=blend,
            coherence=coherence,
            threshold_add=threshold_add,
            blocked=blocked,
            weights=tuple(float(x) for x in w),
        )

def fit_group_weights(prob_matrix, y_true, *, steps: int = 1500, lr: float = 0.05) -> list[float]:
    p = np.asarray(prob_matrix, dtype=float)
    y = np.asarray(y_true, dtype=float)
    if p.ndim != 2 or p.shape[1] != 4 or p.shape[0] != y.size:
        raise ValueError("expected Nx4 probabilities and N labels")
    if y.size < 50:
        raise ValueError("need at least 50 observations to learn weights")

    theta = np.log(np.asarray([0.55, 0.20, 0.15, 0.10], dtype=float))
    for _ in range(steps):
        z = theta - theta.max()
        w = np.exp(z)
        w /= w.sum()
        blend = np.clip(p @ w, 1e-5, 1.0 - 1e-5)
        dloss_dp = (blend - y) / (blend * (1.0 - blend))
        grad = np.zeros(4, dtype=float)
        for k in range(4):
            dp_dtheta = w[k] * (p[:, k] - blend)
            grad[k] = float(np.mean(dloss_dp * dp_dtheta))
        theta -= lr * grad

    w = np.exp(theta - theta.max())
    w /= w.sum()
    return [float(x) for x in w]
