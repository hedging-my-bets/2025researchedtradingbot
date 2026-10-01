from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np
import yaml
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = ROOT.parent
CONFIGS_DIR = ROOT / "configs"
FILES_DIR = REPO_ROOT / "MT5-Platform" / "MQL5" / "Files"
MODELS_DIR = FILES_DIR / "ML_Models"

FEATURES_YAML = CONFIGS_DIR / "features.yaml"
SCALER_JSON = CONFIGS_DIR / "scaler.json"
MODEL_ONNX = MODELS_DIR / "meta_labeler.onnx"
MODEL_ID_FILE = MODELS_DIR / "model_id.txt"

API_PORT = int(os.getenv("INFER_PORT", "8081"))
API_HOST = os.getenv("INFER_HOST", "127.0.0.1")
ALLOW_STUB_MODEL = os.getenv("ALLOW_STUB_MODEL", "0") == "1"

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
    features_version: str
    latency_ms: int

def _hash_files(*paths: Path) -> str:
    h = hashlib.sha256()
    for path in paths:
        h.update(path.read_bytes())
    return h.hexdigest()[:16]

def _load_features_spec() -> Dict[str, Any]:
    spec = yaml.safe_load(FEATURES_YAML.read_text())
    if "meta_features" not in spec:
        raise RuntimeError("features.yaml missing meta_features")
    if len(spec["meta_features"]) != 64:
        raise RuntimeError("feature contract must contain exactly 64 features")
    return spec

def _load_scaler() -> Dict[str, Any]:
    return json.loads(SCALER_JSON.read_text())

FEATURES_SPEC = _load_features_spec()
SCALER_CFG = _load_scaler()
FEATURE_ORDER = [x["name"] for x in FEATURES_SPEC["meta_features"]]
FEATURES_VERSION = _hash_files(FEATURES_YAML, SCALER_JSON)

def _scale_vector(vec: np.ndarray) -> np.ndarray:
    out = vec.astype(np.float32).copy()
    for i, feat in enumerate(FEATURE_ORDER):
        meta = SCALER_CFG["features"].get(feat)
        if not meta or str(meta.get("type", "")).lower() == "category":
            continue
        std = float(meta.get("std", 1.0)) or 1.0
        out[i] = (out[i] - float(meta.get("mean", 0.0))) / std
    return out

ORT_SESS = None
ORT_INPUT = None
ORT_OUTPUT = None
MODEL_ID = MODEL_ONNX.stem

if MODEL_ID_FILE.exists():
    MODEL_ID = MODEL_ID_FILE.read_text().strip() or MODEL_ID

if MODEL_ONNX.exists():
    import onnxruntime as ort
    ORT_SESS = ort.InferenceSession(MODEL_ONNX.as_posix(), providers=["CPUExecutionProvider"])
    ORT_INPUT = ORT_SESS.get_inputs()[0].name
    ORT_OUTPUT = ORT_SESS.get_outputs()[0].name
elif not ALLOW_STUB_MODEL:
    MODEL_ID = "missing-model"

app = FastAPI(title="FXSuite Inference Service", version="2.0.0")

@app.get("/health")
def health() -> Dict[str, Any]:
    return {
        "status": "ok" if ORT_SESS is not None or ALLOW_STUB_MODEL else "degraded",
        "model_loaded": ORT_SESS is not None,
        "model_id": MODEL_ID,
        "features_version": FEATURES_VERSION,
    }

@app.get("/version")
def version() -> Dict[str, Any]:
    return {
        "model_id": MODEL_ID,
        "features_version": FEATURES_VERSION,
        "n_features": len(FEATURE_ORDER),
    }

def _vector(req: InferRequest) -> np.ndarray:
    if req.features is not None:
        vec = np.asarray(req.features, dtype=np.float32)
        if vec.shape != (64,):
            raise HTTPException(400, f"Feature length {vec.shape[0]} != expected 64")
        return vec
    if req.feature_map is not None:
        missing = [name for name in FEATURE_ORDER if name not in req.feature_map]
        if missing:
            raise HTTPException(400, f"Missing feature(s): {missing[:5]}")
        return np.asarray([req.feature_map[name] for name in FEATURE_ORDER], dtype=np.float32)
    raise HTTPException(400, "Provide features or feature_map")

def _infer_prob(vec_scaled: np.ndarray) -> float:
    if ORT_SESS is None:
        if not ALLOW_STUB_MODEL:
            raise HTTPException(503, "Production ONNX model is not installed")
        return 0.5
    result = ORT_SESS.run([ORT_OUTPUT], {ORT_INPUT: vec_scaled.reshape(1, -1)})[0]
    if isinstance(result, list) and result and isinstance(result[0], dict):
        row = result[0]
        return float(row.get(1, row.get("1", 0.5)))
    arr = np.asarray(result)
    return float(arr.ravel()[-1])

def _calibrate(p_raw: float) -> tuple[float, float]:
    # Safe default until pair/regime calibrators are installed.
    p_cal = float(np.clip(p_raw, 0.0, 1.0))
    width = 0.0
    return p_cal, width

@app.post("/infer", response_model=InferResponse)
def infer(req: InferRequest) -> InferResponse:
    t0 = time.perf_counter_ns()
    if req.client_features_version != int(FEATURES_SPEC.get("features_version", 1)):
        raise HTTPException(409, "client feature-version does not match server feature contract")

    vec = _scale_vector(_vector(req))
    p_raw = float(np.clip(_infer_prob(vec), 0.0, 1.0))
    p_cal, width = _calibrate(p_raw)

    return InferResponse(
        correlation_id=req.correlation_id,
        ok=True,
        p_win=p_raw,
        p_cal=p_cal,
        conformal_width=width,
        model_id=MODEL_ID,
        features_version=FEATURES_VERSION,
        latency_ms=int((time.perf_counter_ns() - t0) / 1_000_000),
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=API_HOST, port=API_PORT, log_level="info")
