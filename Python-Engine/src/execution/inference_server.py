# Production-ready REST inference microservice (FastAPI) for MT5 WebRequest.
# - Loads ONNX (onnxruntime) model, features.yaml, scaler.json.
# - Validates feature contract & versions.
# - Accepts either ordered vector or feature_map; returns calibrated p_win.
# - Health & version endpoints for monitoring.
# Requirements: fastapi, uvicorn, onnxruntime, pydantic, numpy, pyyaml

from __future__ import annotations
import os, time, json, hashlib
from typing import List, Optional, Dict, Any
from pathlib import Path

import numpy as np
import onnxruntime as ort
import yaml
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from starlette.responses import JSONResponse

# ---------- Config ----------
ROOT = Path(__file__).resolve().parents[2]
FILES_DIR = ROOT / "MT5-Platform" / "MQL5" / "Files"
MODELS_DIR = FILES_DIR / "ML_Models"
CONFIGS_DIR = ROOT / "configs"

FEATURES_YAML = CONFIGS_DIR / "features.yaml"
SCALER_JSON = CONFIGS_DIR / "scaler.json"
MODEL_ONNX = MODELS_DIR / "meta_labeler.onnx"
MODEL_ID_FILE = MODELS_DIR / "model_id.txt"

API_PORT = int(os.getenv("INFER_PORT", "8081"))
API_HOST = os.getenv("INFER_HOST", "127.0.0.1")

# ---------- IO Schemas ----------
class InferRequest(BaseModel):
    correlation_id: str = Field(..., description="Unique ID from MT5 (UUID/string)")
    # Either provide ordered features (list) OR feature_map (dict)
    features: Optional[List[float]] = None
    feature_map: Optional[Dict[str, float]] = None

class InferResponse(BaseModel):
    correlation_id: str
    ok: bool
    p_win: float
    model_id: str
    features_version: str
    latency_ms: int

# ---------- Utilities ----------
def _hash_files(*paths: Path) -> str:
    h = hashlib.sha256()
    for p in paths:
        h.update(p.read_bytes())
    return h.hexdigest()[:16]

def _load_features_spec() -> Dict[str, Any]:
    with open(FEATURES_YAML, "r") as f:
        spec = yaml.safe_load(f)
    if "meta_features" not in spec:
        raise RuntimeError("features.yaml missing 'meta_features'")
    return spec

def _load_scaler() -> Dict[str, Any]:
    with open(SCALER_JSON, "r") as f:
        return json.load(f)

def _build_order(spec: Dict[str, Any]) -> List[str]:
    return [x["name"] for x in spec["meta_features"]]

def _is_categorical(feat: str, scaler_cfg: Dict[str, Any]) -> bool:
    meta = scaler_cfg["features"].get(feat, {})
    return str(meta.get("type", "")).lower() == "category"

def _scale_vector(vec: np.ndarray, order: List[str], scaler_cfg: Dict[str, Any]) -> np.ndarray:
    out = vec.astype(np.float32).copy()
    for i, feat in enumerate(order):
        meta = scaler_cfg["features"].get(feat, None)
        if not meta:  # unseen: leave as is
            continue
        if _is_categorical(feat, scaler_cfg):
            continue
        mean = float(meta.get("mean", 0.0))
        std = float(meta.get("std", 1.0)) or 1.0
        out[i] = (out[i] - mean) / std
    return out

# ---------- Bootstrap ----------
FEATURES_SPEC = _load_features_spec()
SCALER_CFG = _load_scaler()
FEATURE_ORDER = _build_order(FEATURES_SPEC)
FEATURES_VERSION = _hash_files(FEATURES_YAML, SCALER_JSON)

MODEL_ID = MODEL_ONNX.stem
if MODEL_ID_FILE.exists():
    MODEL_ID = MODEL_ID_FILE.read_text().strip() or MODEL_ID

ORT_SESS = ort.InferenceSession(MODEL_ONNX.as_posix(), providers=["CPUExecutionProvider"])
ORT_INPUT = ORT_SESS.get_inputs()[0].name
ORT_OUTPUT = ORT_SESS.get_outputs()[0].name

app = FastAPI(title="FXSuite Inference Service", version="1.0.0")

# ---------- Endpoints ----------
@app.get("/health")
def health() -> Dict[str, Any]:
    return {"status": "ok", "model_id": MODEL_ID, "features_version": FEATURES_VERSION}

@app.get("/version")
def version() -> Dict[str, Any]:
    return {"model_id": MODEL_ID, "features_version": FEATURES_VERSION, "n_features": len(FEATURE_ORDER)}

@app.post("/infer", response_model=InferResponse)
def infer(req: InferRequest) -> JSONResponse:
    t0 = time.perf_counter_ns()

    # build feature vector
    if req.features is not None:
        vec = np.asarray(req.features, dtype=np.float32)
        if vec.shape[0] != len(FEATURE_ORDER):
            raise HTTPException(400, f"Feature length {vec.shape[0]} != expected {len(FEATURE_ORDER)}")
    elif req.feature_map is not None:
        vec = np.zeros(len(FEATURE_ORDER), dtype=np.float32)
        for i, name in enumerate(FEATURE_ORDER):
            if name not in req.feature_map:
                raise HTTPException(400, f"Missing feature '{name}' in feature_map")
            vec[i] = float(req.feature_map[name])
    else:
        raise HTTPException(400, "Provide either 'features' (ordered list) or 'feature_map' (dict).")

    # scale numeric features
    vec_scaled = _scale_vector(vec, FEATURE_ORDER, SCALER_CFG)

    # run model
    try:
        probs = ORT_SESS.run([ORT_OUTPUT], {ORT_INPUT: vec_scaled.reshape(1, -1)})[0]
        # LightGBM ONNX exports often return raw prob for class 1
        p_win = float(probs.ravel()[-1])
        p_win = max(0.0, min(1.0, p_win))
    except Exception as e:
        raise HTTPException(500, f"Inference error: {e}")

    dt_ms = int((time.perf_counter_ns() - t0) / 1_000_000)
    payload = InferResponse(
        correlation_id=req.correlation_id,
        ok=True,
        p_win=p_win,
        model_id=MODEL_ID,
        features_version=FEATURES_VERSION,
        latency_ms=dt_ms
    ).dict()
    return JSONResponse(payload, status_code=200)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=API_HOST, port=API_PORT, log_level="info")