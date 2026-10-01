from __future__ import annotations

from dataclasses import dataclass
import json
import math
from pathlib import Path
from typing import Iterable

import numpy as np

def _clip_prob(p):
    return np.clip(np.asarray(p, dtype=float), 1e-6, 1.0 - 1e-6)

def calibration_metrics(y_true, y_prob, bins: int = 10) -> dict:
    y = np.asarray(y_true, dtype=float)
    p = np.asarray(y_prob, dtype=float)
    if y.shape != p.shape or y.size == 0:
        raise ValueError("y_true and y_prob must be same non-empty shape")
    brier = float(np.mean((p - y) ** 2))
    edges = np.linspace(0.0, 1.0, bins + 1)
    idx = np.clip(np.digitize(p, edges, right=False) - 1, 0, bins - 1)
    ece = 0.0
    mce = 0.0
    for b in range(bins):
        mask = idx == b
        if not mask.any():
            continue
        gap = abs(float(p[mask].mean()) - float(y[mask].mean()))
        ece += gap * float(mask.mean())
        mce = max(mce, gap)
    return {"ece": ece, "brier": brier, "mce": mce}

@dataclass
class PlattCalibrator:
    a: float = 1.0
    b: float = 0.0

    def fit(self, p_raw, y_true, max_iter: int = 100, l2: float = 1e-6):
        p = _clip_prob(p_raw)
        y = np.asarray(y_true, dtype=float)
        x = np.log(p / (1.0 - p))
        a, b = 1.0, 0.0
        for _ in range(max_iter):
            z = np.clip(a * x + b, -35.0, 35.0)
            q = 1.0 / (1.0 + np.exp(-z))
            w = q * (1.0 - q)
            g = np.array([(x * (q - y)).sum() + l2 * a, (q - y).sum() + l2 * b])
            h = np.array([
                [(w * x * x).sum() + l2, (w * x).sum()],
                [(w * x).sum(), w.sum() + l2],
            ])
            try:
                step = np.linalg.solve(h, g)
            except np.linalg.LinAlgError:
                break
            a -= float(step[0])
            b -= float(step[1])
            if float(np.max(np.abs(step))) < 1e-8:
                break
        self.a, self.b = a, b
        return self

    def transform(self, p_raw):
        p = _clip_prob(p_raw)
        x = np.log(p / (1.0 - p))
        z = np.clip(self.a * x + self.b, -35.0, 35.0)
        return 1.0 / (1.0 + np.exp(-z))

    def to_dict(self):
        return {"method": "platt", "a": self.a, "b": self.b}

@dataclass
class IsotonicCalibrator:
    upper_bounds: list[float] | None = None
    values: list[float] | None = None

    def fit(self, p_raw, y_true):
        p = np.asarray(p_raw, dtype=float)
        y = np.asarray(y_true, dtype=float)
        order = np.argsort(p, kind="mergesort")
        p, y = p[order], y[order]
        blocks = []
        for px, yy in zip(p, y):
            blocks.append([float(px), float(px), float(yy), 1])
            while len(blocks) >= 2:
                left, right = blocks[-2], blocks[-1]
                if left[2] / left[3] <= right[2] / right[3]:
                    break
                merged = [left[0], right[1], left[2] + right[2], left[3] + right[3]]
                blocks[-2:] = [merged]
        self.upper_bounds = [b[1] for b in blocks]
        self.values = [b[2] / b[3] for b in blocks]
        return self

    def transform(self, p_raw):
        if not self.upper_bounds or not self.values:
            raise RuntimeError("isotonic calibrator not fitted")
        p = np.asarray(p_raw, dtype=float)
        idx = np.searchsorted(np.asarray(self.upper_bounds), p, side="left")
        idx = np.clip(idx, 0, len(self.values) - 1)
        return np.asarray(self.values)[idx]

    def to_dict(self):
        return {"method": "isotonic", "upper_bounds": self.upper_bounds, "values": self.values}

@dataclass
class ConformalResidual:
    alpha: float = 0.10
    radius: float = 0.0

    def fit(self, p_cal, y_true):
        p = np.asarray(p_cal, dtype=float)
        y = np.asarray(y_true, dtype=float)
        residual = np.abs(y - p)
        if residual.size == 0:
            raise ValueError("empty residual set")
        q = min(1.0, math.ceil((residual.size + 1) * (1.0 - self.alpha)) / residual.size)
        self.radius = float(np.quantile(residual, q, method="higher"))
        return self

    @property
    def width(self) -> float:
        return min(1.0, 2.0 * self.radius)

    def interval(self, p_cal: float) -> tuple[float, float]:
        return max(0.0, p_cal - self.radius), min(1.0, p_cal + self.radius)

class CalibrationSelector:
    def fit_select(self, train_p, train_y, valid_p, valid_y) -> dict:
        platt = PlattCalibrator().fit(train_p, train_y)
        iso = IsotonicCalibrator().fit(train_p, train_y)
        p_platt = platt.transform(valid_p)
        p_iso = iso.transform(valid_p)
        m_platt = calibration_metrics(valid_y, p_platt)
        m_iso = calibration_metrics(valid_y, p_iso)
        chosen = platt if m_platt["ece"] <= m_iso["ece"] else iso
        chosen_p = p_platt if chosen is platt else p_iso
        conformal = ConformalResidual(alpha=0.10).fit(chosen_p, valid_y)
        return {
            "calibrator": chosen.to_dict(),
            "metrics": m_platt if chosen is platt else m_iso,
            "conformal": {"alpha": conformal.alpha, "radius": conformal.radius, "width": conformal.width},
        }

class CalibrationArtifact:
    def __init__(self, payload: dict):
        self.payload = payload
        self.calibrator_id = str(payload.get("calibrator_id", "identity-v1"))

    @classmethod
    def load(cls, path: Path):
        if not path.exists():
            return cls({"method": "identity", "calibrator_id": "identity-v1", "conformal_width": 0.0})
        return cls(json.loads(path.read_text()))

    def transform(self, p_raw: float) -> tuple[float, float]:
        method = self.payload.get("method", self.payload.get("calibrator", {}).get("method", "identity"))
        cfg = self.payload.get("calibrator", self.payload)
        p = float(np.clip(p_raw, 0.0, 1.0))
        if method == "platt":
            cal = PlattCalibrator(float(cfg["a"]), float(cfg["b"]))
            out = float(cal.transform([p])[0])
        elif method == "isotonic":
            cal = IsotonicCalibrator(list(cfg["upper_bounds"]), list(cfg["values"]))
            out = float(cal.transform([p])[0])
        else:
            out = p
        width = float(self.payload.get("conformal", {}).get("width", self.payload.get("conformal_width", 0.0)))
        return out, width
