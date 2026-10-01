from __future__ import annotations

import json
from pathlib import Path
import re

import numpy as np

from calibration.calibrators import CalibrationArtifact
from ml_pipeline.model_registry import sha256_file

_SAFE = re.compile(r"^[A-Za-z0-9._-]+$")

class ArtifactValidationError(RuntimeError):
    pass

def _safe_part(value: str, label: str) -> str:
    value = str(value).strip()
    if not value or not _SAFE.fullmatch(value) or ".." in value:
        raise ValueError(f"invalid {label}: {value!r}")
    return value

def artifact_dir(root: Path, symbol: str, timeframe: str) -> Path:
    return root / _safe_part(symbol.upper(), "symbol") / _safe_part(timeframe, "timeframe")

def validate_artifact_hashes(
    directory: Path,
    *,
    features_path: Path,
    scaler_path: Path,
) -> dict:
    manifest_path = directory / "manifest.json"
    model_path = directory / "meta_labeler.onnx"
    calibration_path = directory / "calibration.json"

    for path in (manifest_path, model_path, calibration_path, features_path, scaler_path):
        if not path.exists():
            raise ArtifactValidationError(f"missing artifact: {path}")

    manifest = json.loads(manifest_path.read_text())
    expected = {
        "features_hash": sha256_file(features_path),
        "scaler_hash": sha256_file(scaler_path),
        "model_hash": sha256_file(model_path),
        "calibration_hash": sha256_file(calibration_path),
    }
    for key, actual in expected.items():
        if manifest.get(key) != actual:
            raise ArtifactValidationError(
                f"{key} mismatch: manifest={manifest.get(key)} actual={actual}"
            )
    return manifest

class ModelRuntime:
    def __init__(
        self,
        directory: Path,
        *,
        features_path: Path,
        scaler_path: Path,
    ):
        self.directory = directory
        self.manifest = validate_artifact_hashes(
            directory, features_path=features_path, scaler_path=scaler_path
        )
        self.model_id = str(self.manifest["model_id"])
        self.calibration = CalibrationArtifact.load(directory / "calibration.json")

        try:
            import onnxruntime as ort
        except ImportError as exc:
            raise RuntimeError("onnxruntime is required for live inference") from exc

        model_path = directory / "meta_labeler.onnx"
        self.session = ort.InferenceSession(
            model_path.as_posix(), providers=["CPUExecutionProvider"]
        )
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name

    def infer(self, vec_scaled: np.ndarray) -> tuple[float, float, float]:
        result = self.session.run(
            [self.output_name],
            {self.input_name: vec_scaled.reshape(1, -1).astype(np.float32)},
        )[0]
        if isinstance(result, list) and result and isinstance(result[0], dict):
            row = result[0]
            p_raw = float(row.get(1, row.get("1", 0.5)))
        else:
            p_raw = float(np.asarray(result).ravel()[-1])
        p_raw = float(np.clip(p_raw, 0.0, 1.0))
        p_cal, width = self.calibration.transform(p_raw)
        return p_raw, float(p_cal), float(width)

class ModelRouter:
    def __init__(self, root: Path, *, features_path: Path, scaler_path: Path):
        self.root = root
        self.features_path = features_path
        self.scaler_path = scaler_path
        self._cache: dict[tuple[str, str], ModelRuntime] = {}

    def directory(self, symbol: str, timeframe: str) -> Path:
        return artifact_dir(self.root, symbol, timeframe)

    def available_routes(self) -> list[str]:
        if not self.root.exists():
            return []
        routes = []
        for manifest in self.root.glob("*/*/manifest.json"):
            routes.append(f"{manifest.parent.parent.name}/{manifest.parent.name}")
        return sorted(routes)

    def has_route(self, symbol: str, timeframe: str) -> bool:
        d = self.directory(symbol, timeframe)
        return (
            (d / "manifest.json").exists()
            and (d / "meta_labeler.onnx").exists()
            and (d / "calibration.json").exists()
        )

    def get(self, symbol: str, timeframe: str) -> ModelRuntime | None:
        key = (_safe_part(symbol.upper(), "symbol"), _safe_part(timeframe, "timeframe"))
        if key in self._cache:
            return self._cache[key]
        if not self.has_route(*key):
            return None
        runtime = ModelRuntime(
            self.directory(*key),
            features_path=self.features_path,
            scaler_path=self.scaler_path,
        )
        self._cache[key] = runtime
        return runtime

    def predict(
        self, symbol: str, timeframe: str, vec_scaled: np.ndarray
    ) -> tuple[float, float, float, str, str] | None:
        runtime = self.get(symbol, timeframe)
        if runtime is None:
            return None
        p_raw, p_cal, width = runtime.infer(vec_scaled)
        return (
            p_raw,
            p_cal,
            width,
            runtime.model_id,
            runtime.calibration.calibrator_id,
        )
