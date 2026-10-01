from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "Python-Engine" / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from execution.model_router import validate_artifact_hashes

FEATURES = ROOT / "Python-Engine" / "configs" / "features.yaml"
SCALER = ROOT / "Python-Engine" / "configs" / "scaler.json"
DEFAULT_LIVE_ROOT = ROOT / "Python-Engine" / "artifacts" / "live"

REQUIRED = ("manifest.json", "meta_labeler.onnx", "calibration.json")

def promote(
    candidate: Path,
    decision_path: Path,
    *,
    live_root: Path = DEFAULT_LIVE_ROOT,
    replace: bool = False,
) -> Path:
    decision = json.loads(decision_path.read_text())
    if decision.get("eligible") is not True:
        raise RuntimeError("promotion decision is not eligible=true")

    manifest = validate_artifact_hashes(
        candidate,
        features_path=FEATURES,
        scaler_path=SCALER,
    )
    symbol = str(manifest.get("symbol", "")).upper()
    timeframe = str(manifest.get("timeframe", ""))
    model_id = str(manifest.get("model_id", ""))
    if not symbol or not timeframe or not model_id:
        raise RuntimeError("manifest missing symbol/timeframe/model_id")

    target = live_root / symbol / timeframe
    target.parent.mkdir(parents=True, exist_ok=True)

    if target.exists() and not replace:
        raise FileExistsError(f"live route already exists: {target}")

    staging = Path(tempfile.mkdtemp(prefix=f".{symbol}-{timeframe}-", dir=str(target.parent)))
    backup = target.with_name(target.name + ".previous")
    try:
        for name in REQUIRED:
            shutil.copy2(candidate / name, staging / name)
        for optional in ("MODEL_CARD.md", "research_report.json"):
            src = candidate / optional
            if src.exists():
                shutil.copy2(src, staging / optional)

        # Validate the exact bytes that will be served.
        validate_artifact_hashes(
            staging,
            features_path=FEATURES,
            scaler_path=SCALER,
        )

        if target.exists():
            if backup.exists():
                shutil.rmtree(backup)
            os.replace(target, backup)

        try:
            os.replace(staging, target)
        except Exception:
            if backup.exists() and not target.exists():
                os.replace(backup, target)
            raise

        if backup.exists():
            shutil.rmtree(backup)

        receipt = {
            "model_id": model_id,
            "symbol": symbol,
            "timeframe": timeframe,
            "promotion_decision": str(decision_path),
            "eligible": True,
        }
        (target / "PROMOTION_RECEIPT.json").write_text(
            json.dumps(receipt, indent=2, sort_keys=True) + "\n"
        )
        return target
    finally:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--candidate", required=True, type=Path)
    p.add_argument("--decision", required=True, type=Path)
    p.add_argument("--live-root", type=Path, default=DEFAULT_LIVE_ROOT)
    p.add_argument("--replace", action="store_true")
    args = p.parse_args()

    target = promote(
        args.candidate,
        args.decision,
        live_root=args.live_root,
        replace=args.replace,
    )
    print(target)
    print("Candidate copied to live artifact route; restart/reload inference explicitly.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
