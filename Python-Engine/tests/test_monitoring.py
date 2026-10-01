from pathlib import Path
import sys
import numpy as np

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from monitoring.feature_monitor import FeatureDriftDetector, PageHinkley
from monitoring.model_decay import ModelDecayMonitor

def test_psi_zeroish_for_same_distribution():
    x = np.linspace(-2.0, 2.0, 1000)
    score = FeatureDriftDetector.psi(x, x.copy())
    assert score < 1e-9

def test_psi_detects_shift():
    x = np.linspace(-2.0, 2.0, 1000)
    y = x + 2.0
    assert FeatureDriftDetector.psi(x, y) > 0.2

def test_page_hinkley_detects_mean_shift():
    ph = PageHinkley(delta=0.001, threshold=2.0, alpha=1.0)
    detected = False
    for value in [0.0] * 100 + [1.0] * 100:
        detected = detected or ph.update(value)
    assert detected

def test_model_decay_metrics():
    y = np.array([0.0, 1.0] * 100)
    p = np.array([0.1, 0.9] * 100)
    m = ModelDecayMonitor.metrics(y, p)
    assert m["brier"] < 0.02
