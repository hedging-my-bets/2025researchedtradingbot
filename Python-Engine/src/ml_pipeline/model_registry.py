from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import tempfile

@dataclass(frozen=True)
class ModelManifest:
    model_id: str
    symbol: str
    timeframe: str
    dataset_hash: str
    features_hash: str
    scaler_hash: str
    model_hash: str
    calibration_hash: str
    created_utc: str
    cv_summary: dict
    metrics: dict

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def build_manifest(
    *,
    model_id: str,
    symbol: str,
    timeframe: str,
    dataset_path: Path,
    features_path: Path,
    scaler_path: Path,
    model_path: Path,
    calibration_path: Path,
    cv_summary: dict,
    metrics: dict,
) -> ModelManifest:
    return ModelManifest(
        model_id=model_id,
        symbol=symbol,
        timeframe=timeframe,
        dataset_hash=sha256_file(dataset_path),
        features_hash=sha256_file(features_path),
        scaler_hash=sha256_file(scaler_path),
        model_hash=sha256_file(model_path),
        calibration_hash=sha256_file(calibration_path),
        created_utc=datetime.now(timezone.utc).isoformat(),
        cv_summary=cv_summary,
        metrics=metrics,
    )

def write_manifest_atomic(manifest: ModelManifest, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="manifest_", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(asdict(manifest), f, sort_keys=True, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
