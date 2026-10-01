from pathlib import Path
import sys
import pandas as pd
import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
sys.path.insert(0, str(SRC))

from training.dataset_contract import load_training_frame

def names():
    spec = yaml.safe_load((ROOT / "configs" / "features.yaml").read_text())
    return [x["name"] for x in spec["meta_features"]]

def make_frame(n=10):
    data = {"timestamp": pd.date_range("2024-01-01", periods=n, freq="h", tz="UTC")}
    for name in names():
        data[name] = [0.0] * n
    data["y_net_profitable"] = [0, 1] * (n // 2) + ([0] if n % 2 else [])
    data["realized_r_after_costs"] = [0.2 if x else -0.1 for x in data["y_net_profitable"]]
    return pd.DataFrame(data)

def test_training_contract_sorts_chronologically(tmp_path):
    df = make_frame(10).iloc[::-1]
    path = tmp_path / "data.csv"
    df.to_csv(path, index=False)
    tf = load_training_frame(path, feature_names=names())
    assert tf.frame["timestamp"].is_monotonic_increasing
    assert tf.return_col == "realized_r_after_costs"

def test_training_contract_rejects_missing_feature(tmp_path):
    df = make_frame(10).drop(columns=[names()[3]])
    path = tmp_path / "data.csv"
    df.to_csv(path, index=False)
    with pytest.raises(ValueError):
        load_training_frame(path, feature_names=names())
