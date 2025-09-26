import json, yaml, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec_path = ROOT / "configs" / "features.yaml"
scaler_path = ROOT / "configs" / "scaler.json"

def verify_all_connections():
    spec = yaml.safe_load(spec_path.read_text())
    scaler = json.loads(scaler_path.read_text())
    names = [x["name"] for x in spec["meta_features"]]
    missing = [n for n in names if n not in scaler["features"]]
    if missing:
        print("ERROR: scaler.json missing features:", missing)
        sys.exit(1)
    print("OK: features.yaml ↔ scaler.json align.")

if __name__ == "__main__":
    verify_all_connections()