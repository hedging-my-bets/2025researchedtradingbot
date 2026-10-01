from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "release_fingerprint.json"

EXCLUDED_NAMES = {
    "BuildFingerprint.mqh",  # generated from the fingerprint itself
    "live_approval.json",
    "live_approval.csv",
}

def tracked_paths(root: Path = ROOT) -> list[Path]:
    patterns = [
        "MT5-Platform/MQL5/Experts/FXSuite/**/*.mq5",
        "MT5-Platform/MQL5/Include/FXSuite/**/*.mqh",
        "MT5-Platform/MQL5/Files/mtf_weights.csv",
        "Python-Engine/configs/*.json",
        "Python-Engine/configs/*.yaml",
        "Python-Engine/src/execution/inference_server.py",
        "Python-Engine/src/execution/model_router.py",
        "Python-Engine/src/features/registry.py",
        "Python-Engine/src/calibration/calibrators.py",
        "Python-Engine/src/ml_pipeline/mtf_blender.py",
    ]

    found: set[Path] = set()
    for pattern in patterns:
        for path in root.glob(pattern):
            if path.is_file() and path.name not in EXCLUDED_NAMES:
                found.add(path)

    # Local production model artifacts are deliberately included when present,
    # even though they are ignored by git.
    live_root = root / "Python-Engine" / "artifacts" / "live"
    if live_root.exists():
        for pattern in ("**/manifest.json", "**/calibration.json", "**/meta_labeler.onnx"):
            for path in live_root.glob(pattern):
                if path.is_file():
                    found.add(path)

    return sorted(found, key=lambda p: p.relative_to(root).as_posix())

def fingerprint(root: Path = ROOT) -> str:
    h = hashlib.sha256()
    paths = tracked_paths(root)
    if not paths:
        raise RuntimeError("no live-relevant files found for release fingerprint")

    for path in paths:
        rel = path.relative_to(root).as_posix()
        h.update(rel.encode("utf-8"))
        h.update(b"\0")
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                h.update(chunk)
        h.update(b"\0")
    return h.hexdigest()

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--list", action="store_true", help="List fingerprinted paths.")
    args = parser.parse_args()

    paths = tracked_paths()
    if args.list:
        for path in paths:
            print(path.relative_to(ROOT).as_posix())

    value = fingerprint()
    if args.check:
        print("release_fingerprint", value)
        print("tracked_files", len(paths))
        return 0

    OUT.write_text(
        json.dumps(
            {
                "sha256": value,
                "tracked_files": [p.relative_to(ROOT).as_posix() for p in paths],
            },
            indent=2,
        )
        + "\n"
    )
    print(OUT)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
