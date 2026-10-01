import json
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]

def test_feature_contract_is_64_and_scaler_complete():
    spec = yaml.safe_load((ROOT / "configs" / "features.yaml").read_text())
    scaler = json.loads((ROOT / "configs" / "scaler.json").read_text())
    names = [x["name"] for x in spec["meta_features"]]
    assert len(names) == 64
    assert len(set(names)) == 64
    assert all(name in scaler["features"] for name in names)

def test_legacy_feature_indices_are_stable():
    spec = yaml.safe_load((ROOT / "configs" / "features.yaml").read_text())
    names = [x["name"] for x in spec["meta_features"]]
    assert names[0] == "ret_1"
    assert names[1] == "ret_5"
    assert names[2] == "atr"
    assert names[21] == "minutes_to_high_news"
