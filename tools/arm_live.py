from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build_release_fingerprint import fingerprint

APPROVAL = ROOT / "MT5-Platform" / "MQL5" / "Files" / "FXSuite" / "live_approval.json"
PHRASE = "ARM LIVE FXSUITE"

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--phrase", required=True)
    args = p.parse_args()
    if args.phrase != PHRASE:
        print(f"Refusing: exact phrase required: {PHRASE}")
        return 2

    current = fingerprint()
    APPROVAL.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "approved": True,
        "fingerprint": current,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "warning": "Approval is invalid after any tracked strategy/risk/execution/config change.",
    }
    APPROVAL.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Live approval created for fingerprint {current}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
