from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build_release_fingerprint import fingerprint

APPROVAL = ROOT / "MT5-Platform" / "MQL5" / "Files" / "FXSuite" / "live_approval.json"

def verify() -> bool:
    if not APPROVAL.exists():
        return False
    try:
        payload = json.loads(APPROVAL.read_text())
    except Exception:
        return False
    return bool(payload.get("approved")) and payload.get("fingerprint") == fingerprint()

if __name__ == "__main__":
    ok = verify()
    print("VALID" if ok else "INVALID")
    raise SystemExit(0 if ok else 1)
