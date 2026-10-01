import json
import sys
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
spec_path = ROOT / "Python-Engine" / "configs" / "features.yaml"
scaler_path = ROOT / "Python-Engine" / "configs" / "scaler.json"

def verify_all_connections():
    spec = yaml.safe_load(spec_path.read_text())
    scaler = json.loads(scaler_path.read_text())
    names = [x["name"] for x in spec["meta_features"]]
    missing = [n for n in names if n not in scaler["features"]]
    if len(names) != 64:
        print("ERROR: expected 64 features, got", len(names))
        sys.exit(1)
    if missing:
        print("ERROR: scaler.json missing features:", missing)
        sys.exit(1)
    print("OK: 64-feature contract and scaler align.")

if __name__ == "__main__":
    verify_all_connections()
