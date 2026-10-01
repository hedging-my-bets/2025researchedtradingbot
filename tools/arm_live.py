from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build_release_fingerprint import fingerprint

APPROVAL_JSON = ROOT / "MT5-Platform" / "MQL5" / "Files" / "FXSuite" / "live_approval.json"
APPROVAL_CSV = ROOT / "MT5-Platform" / "MQL5" / "Files" / "FXSuite" / "live_approval.csv"
BUILD_INCLUDE = ROOT / "MT5-Platform" / "MQL5" / "Include" / "FXSuite" / "Core" / "BuildFingerprint.mqh"
PHRASE = "ARM LIVE FXSUITE"

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--phrase", required=True)
    args = p.parse_args()
    if args.phrase != PHRASE:
        print(f"Refusing: exact phrase required: {PHRASE}")
        return 2

    current = fingerprint()
    created = datetime.now(timezone.utc).isoformat()

    APPROVAL_JSON.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "approved": True,
        "fingerprint": current,
        "created_utc": created,
        "warning": "Approval is invalid after any tracked strategy/risk/execution/config change.",
    }
    APPROVAL_JSON.write_text(json.dumps(payload, indent=2) + "\n")
    APPROVAL_CSV.write_text(
        "approved,fingerprint,created_utc\n"
        f"1,{current},{created}\n"
    )

    BUILD_INCLUDE.write_text(
        '#property strict\n'
        '// Generated locally by tools/arm_live.py. Re-arm after any tracked change.\n'
        f'#define FXSUITE_BUILD_FINGERPRINT "{current}"\n'
    )

    print(f"Live approval + build fingerprint created for {current}")
    print("Compile the EA only after this step; re-arm after any tracked source/config change.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
