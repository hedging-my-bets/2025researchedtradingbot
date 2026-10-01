from pathlib import Path
import sys
import numpy as np

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from calibration.calibrators import (
    CalibrationArtifact,
    CalibrationSelector,
    ConformalResidual,
    IsotonicCalibrator,
    PlattCalibrator,
    calibration_metrics,
)

def test_platt_probabilities_are_bounded():
    p = np.linspace(0.05, 0.95, 100)
    y = (p > 0.55).astype(float)
    cal = PlattCalibrator().fit(p, y)
    out = cal.transform(p)
    assert np.all(out >= 0.0)
    assert np.all(out <= 1.0)

def test_isotonic_is_monotone():
    p = np.linspace(0.01, 0.99, 80)
    y = (p + 0.15 * np.sin(np.arange(80)) > 0.5).astype(float)
    out = IsotonicCalibrator().fit(p, y).transform(p)
    assert np.all(np.diff(out) >= -1e-12)

def test_selector_returns_metrics_and_conformal():
    p = np.linspace(0.05, 0.95, 200)
    y = (p > 0.5).astype(float)
    result = CalibrationSelector().fit_select(p[:120], y[:120], p[120:], y[120:])
    assert result["calibrator"]["method"] in {"platt", "isotonic"}
    assert "ece" in result["metrics"]
    assert 0.0 <= result["conformal"]["width"] <= 1.0

def test_identity_artifact():
    artifact = CalibrationArtifact({"method": "identity", "conformal_width": 0.2})
    p, width = artifact.transform(0.61)
    assert p == 0.61
    assert width == 0.2

def test_metrics_perfect_forecast():
    y = np.array([0, 1, 0, 1], dtype=float)
    assert calibration_metrics(y, y)["brier"] == 0.0
