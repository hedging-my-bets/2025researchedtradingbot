from pathlib import Path
import math
import sys
import pytest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
sys.path.insert(0, str(SRC))

from features.registry import FeatureRegistry

def registry():
    return FeatureRegistry.load(ROOT / "configs" / "features.yaml")

def test_registry_has_full_metadata():
    r = registry()
    assert len(r.specs) == 64
    assert r.registry_version == "omega-v1"
    assert all(s.unit for s in r.specs)
    assert all(s.minimum <= s.maximum for s in r.specs)

def test_registry_clips_known_outlier():
    r = registry()
    values = [0.0] * 64
    values[15] = 99.0
    clean = r.sanitize(values)
    assert clean[15] == 23.0

def test_registry_rejects_nan():
    r = registry()
    values = [0.0] * 64
    values[7] = math.nan
    with pytest.raises(ValueError):
        r.sanitize(values)
