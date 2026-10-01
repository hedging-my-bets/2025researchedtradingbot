from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRACKED = [
    ROOT / "MT5-Platform/MQL5/Experts/FXSuite/MASTER_CONTROLLER.mq5",
    ROOT / "MT5-Platform/MQL5/Include/FXSuite/Core/OrderManager.mqh",
    ROOT / "MT5-Platform/MQL5/Include/FXSuite/Core/RiskManager.mqh",
    ROOT / "MT5-Platform/MQL5/Include/FXSuite/Core/PortfolioControl.mqh",
    ROOT / "Python-Engine/configs/features.yaml",
    ROOT / "Python-Engine/configs/scaler.json",
    ROOT / "Python-Engine/configs/calibration.json",
]
OUT = ROOT / "release_fingerprint.json"

def fingerprint() -> str:
    h = hashlib.sha256()
    for path in TRACKED:
        h.update(str(path.relative_to(ROOT)).encode())
        h.update(b"\0")
        h.update(path.read_bytes())
        h.update(b"\0")
    return h.hexdigest()

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    value = fingerprint()
    if args.check:
        print("release_fingerprint", value)
        return 0
    OUT.write_text(json.dumps({"sha256": value}, indent=2) + "\n")
    print(OUT)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
