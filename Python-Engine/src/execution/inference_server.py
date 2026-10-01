from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import sys
import time
from typing import Any, Dict, List, Optional

import numpy as np
import yaml
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

ENGINE_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = ENGINE_ROOT.parent
SRC_DIR = ENGINE_ROOT / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from calibration.calibrators import CalibrationArtifact
from execution.model_router import ModelRouter, timeframe_key
from features.registry import FeatureRegistry

CONFIGS_DIR = ENGINE_ROOT / "configs"
FILES_DIR = REPO_ROOT / "MT5-Platform" / "MQL5" / "Files"
MODELS_DIR = FILES_DIR / "ML_Models"
PAIR_MODEL_ROOT = Path(
    os.getenv("PAIR_MODEL_ROOT", str(ENGINE_ROOT / "artifacts" / "live"))
)

FEATURES_YAML = CONFIGS_DIR / "features.yaml"
SCALER_JSON = CONFIGS_DIR / "scaler.json"
CALIBRATION_JSON = CONFIGS_DIR / "calibration.json"
MODEL_ONNX = MODELS_DIR / "meta_labeler.onnx"
MODEL_ID_FILE = MODELS_DIR / "model_id.txt"

API_PORT = int(os.getenv("INFER_PORT", "8081"))
API_HOST = os.getenv("INFER_HOST", "127.0.0.1")
ALLOW_STUB_MODEL = os.getenv("ALLOW_STUB_MODEL", "0") == "1"
REQUIRE_PAIR_MODEL = os.getenv("REQUIRE_PAIR_MODEL", "0") == "1"

class InferRequest(BaseModel):
    correlation_id: str = Field(..., min_length=1)
    symbol: str = ""
    timeframe: int = 0
    client_features_version: int = 1
    features: Optional[List[float]] = None
    feature_map: Optional[Dict[str, float]] = None

class InferResponse(BaseModel):
    correlation_id: str
    ok: bool
    p_win: float
    p_cal: float
    conformal_width: float
    model_id: str
    calibrator_id: str
    route: str
    features_version: str
    latency_ms: int

def _hash_files(*paths: Path) -> str:
    h = hashlib.sha256()
    for path in paths:
        h.update(path.read_bytes())
    return h.hexdigest()[:16]

def _load_scaler() -> Dict[str, Any]:
    return json.loads(SCALER_JSON.read_text())

FEATURES_SPEC = yaml.safe_load(FEATURES_YAML.read_text())
FEATURE_REGISTRY = FeatureRegistry.load(FEATURES_YAML)
SCALER_CFG = _load_scaler()
FEATURE_ORDER = FEATURE_REGISTRY.names
FEATURES_VERSION = _hash_files(FEATURES_YAML, SCALER_JSON)
GLOBAL_CALIBRATION = CalibrationArtifact.load(CALIBRATION_JSON)
ROUTER = ModelRouter(
    PAIR_MODEL_ROOT,
    features_path=FEATURES_YAML,
    scaler_path=SCALER_JSON,
)

def _scale_vector(vec: np.ndarray) -> np.ndarray:
    out = vec.astype(np.float32).copy()
    for i, feat in enumerate(FEATURE_ORDER):
        meta = SCALER_CFG["features"].get(feat)
        if not meta or str(meta.get("type", "")).lower() == "category":
            continue
        std = float(meta.get("std", 1.0)) or 1.0
        out[i] = (out[i] - float(meta.get("mean", 0.0))) / std
    return out

GLOBAL_SESSION = None
GLOBAL_INPUT = None
GLOBAL_OUTPUT = None
GLOBAL_MODEL_ID = MODEL_ONNX.stem

if MODEL_ID_FILE.exists():
    GLOBAL_MODEL_ID = MODEL_ID_FILE.read_text().strip() or GLOBAL_MODEL_ID

if MODEL_ONNX.exists():
    import onnxruntime as ort
    GLOBAL_SESSION = ort.InferenceSession(
        MODEL_ONNX.as_posix(), providers=["CPUExecutionProvider"]
    )
    GLOBAL_INPUT = GLOBAL_SESSION.get_inputs()[0].name
    GLOBAL_OUTPUT = GLOBAL_SESSION.get_outputs()[0].name
elif not ALLOW_STUB_MODEL:
    GLOBAL_MODEL_ID = "missing-model"

app = FastAPI(title="FXSuite Inference Service", version="3.0.0")

@app.get("/health")
def health() -> Dict[str, Any]:
    routes = ROUTER.available_routes()
    serving = bool(routes) or GLOBAL_SESSION is not None or ALLOW_STUB_MODEL
    return {
        "status": "ok" if serving else "degraded",
        "pair_routes": routes,
        "global_model_loaded": GLOBAL_SESSION is not None,
        "global_model_id": GLOBAL_MODEL_ID,
        "global_calibrator_id": GLOBAL_CALIBRATION.calibrator_id,
        "features_version": FEATURES_VERSION,
        "registry_version": FEATURE_REGISTRY.registry_version,
        "require_pair_model": REQUIRE_PAIR_MODEL,
    }

@app.get("/version")
def version() -> Dict[str, Any]:
    return {
        "global_model_id": GLOBAL_MODEL_ID,
        "features_version": FEATURES_VERSION,
        "registry_version": FEATURE_REGISTRY.registry_version,
        "n_features": len(FEATURE_ORDER),
        "pair_routes": ROUTER.available_routes(),
    }

def _vector(req: InferRequest) -> np.ndarray:
    if req.features is not None:
        raw = req.features
    elif req.feature_map is not None:
        missing = [name for name in FEATURE_ORDER if name not in req.feature_map]
        if missing:
            raise HTTPException(400, f"Missing feature(s): {missing[:5]}")
        raw = [req.feature_map[name] for name in FEATURE_ORDER]
    else:
        raise HTTPException(400, "Provide features or feature_map")

    try:
        clean = FEATURE_REGISTRY.sanitize(raw)
    except (TypeError, ValueError) as exc:
        raise HTTPException(422, str(exc)) from exc
    return np.asarray(clean, dtype=np.float32)

def _global_infer(vec_scaled: np.ndarray) -> float:
    if GLOBAL_SESSION is None:
        if not ALLOW_STUB_MODEL:
            raise HTTPException(503, "No production model is available")
        return 0.5

    result = GLOBAL_SESSION.run(
        [GLOBAL_OUTPUT],
        {GLOBAL_INPUT: vec_scaled.reshape(1, -1).astype(np.float32)},
    )[0]
    if isinstance(result, list) and result and isinstance(result[0], dict):
        row = result[0]
        return float(row.get(1, row.get("1", 0.5)))
    return float(np.asarray(result).ravel()[-1])

@app.post("/infer", response_model=InferResponse)
def infer(req: InferRequest) -> InferResponse:
    t0 = time.perf_counter_ns()

    if req.client_features_version != FEATURE_REGISTRY.version:
        raise HTTPException(
            409,
            f"client feature-version {req.client_features_version} "
            f"!= server {FEATURE_REGISTRY.version}",
        )

    vec = _scale_vector(_vector(req))
    tf_key = timeframe_key(req.timeframe)
    routed = None
    if req.symbol and req.timeframe:
        try:
            routed = ROUTER.predict(req.symbol, tf_key, vec)
        except (ValueError, RuntimeError) as exc:
            raise HTTPException(503, f"pair model invalid: {exc}") from exc

    if routed is not None:
        p_raw, p_cal, width, model_id, calibrator_id = routed
        route = f"{req.symbol.upper()}/{tf_key}"
    else:
        if REQUIRE_PAIR_MODEL:
            raise HTTPException(
                503, f"required pair model missing for {req.symbol}/{tf_key}"
            )
        p_raw = float(np.clip(_global_infer(vec), 0.0, 1.0))
        p_cal, width = GLOBAL_CALIBRATION.transform(p_raw)
        model_id = GLOBAL_MODEL_ID
        calibrator_id = GLOBAL_CALIBRATION.calibrator_id
        route = "global-fallback"

    return InferResponse(
        correlation_id=req.correlation_id,
        ok=True,
        p_win=float(p_raw),
        p_cal=float(p_cal),
        conformal_width=float(width),
        model_id=model_id,
        calibrator_id=calibrator_id,
        route=route,
        features_version=FEATURES_VERSION,
        latency_ms=int((time.perf_counter_ns() - t0) / 1_000_000),
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=API_HOST, port=API_PORT, log_level="info")
