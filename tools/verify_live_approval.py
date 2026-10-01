from __future__ import annotations

import json
import re
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build_release_fingerprint import fingerprint

APPROVAL_JSON = ROOT / "MT5-Platform" / "MQL5" / "Files" / "FXSuite" / "live_approval.json"
BUILD_INCLUDE = ROOT / "MT5-Platform" / "MQL5" / "Include" / "FXSuite" / "Core" / "BuildFingerprint.mqh"

def embedded_fingerprint() -> str | None:
    if not BUILD_INCLUDE.exists():
        return None
    m = re.search(r'FXSUITE_BUILD_FINGERPRINT\s+"([^"]+)"', BUILD_INCLUDE.read_text())
    return m.group(1) if m else None

def verify() -> bool:
    if not APPROVAL_JSON.exists():
        return False
    try:
        payload = json.loads(APPROVAL_JSON.read_text())
    except Exception:
        return False

    current = fingerprint()
    embedded = embedded_fingerprint()
    return (
        bool(payload.get("approved"))
        and payload.get("fingerprint") == current
        and embedded == current
        and embedded != "UNARMED"
    )

if __name__ == "__main__":
    ok = verify()
    print("VALID" if ok else "INVALID")
    raise SystemExit(0 if ok else 1)
