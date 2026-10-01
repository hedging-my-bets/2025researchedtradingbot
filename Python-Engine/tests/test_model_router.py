from pathlib import Path
import json
import sys
import pytest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
sys.path.insert(0, str(SRC))

from execution.model_router import (
    ArtifactValidationError,
    artifact_dir,
    validate_artifact_hashes,
    timeframe_key,
)
from ml_pipeline.model_registry import sha256_file

def test_artifact_dir_rejects_traversal(tmp_path):
    with pytest.raises(ValueError):
        artifact_dir(tmp_path, "../EURUSD", "15")
    with pytest.raises(ValueError):
        artifact_dir(tmp_path, "EURUSD", "../../15")

def test_manifest_hash_validation(tmp_path):
    d = tmp_path / "EURUSD" / "15"
    d.mkdir(parents=True)
    features = tmp_path / "features.yaml"
    scaler = tmp_path / "scaler.json"
    model = d / "meta_labeler.onnx"
    calibration = d / "calibration.json"

    features.write_text("features")
    scaler.write_text("{}")
    model.write_bytes(b"model-bytes")
    calibration.write_text('{"method":"identity"}')

    manifest = {
        "model_id":"m1",
        "features_hash":sha256_file(features),
        "scaler_hash":sha256_file(scaler),
        "model_hash":sha256_file(model),
        "calibration_hash":sha256_file(calibration),
    }
    (d / "manifest.json").write_text(json.dumps(manifest))

    out = validate_artifact_hashes(d, features_path=features, scaler_path=scaler)
    assert out["model_id"] == "m1"

    model.write_bytes(b"tampered")
    with pytest.raises(ArtifactValidationError):
        validate_artifact_hashes(d, features_path=features, scaler_path=scaler)

def test_inference_server_is_wired_to_registry_and_router():
    src = (SRC / "execution" / "inference_server.py").read_text()
    assert "FEATURE_REGISTRY.sanitize" in src
    assert "ROUTER.predict" in src
    assert "REQUIRE_PAIR_MODEL" in src

def test_mql_timeframe_keys():
    assert timeframe_key(15) == "M15"
    assert timeframe_key(16385) == "H1"
    assert timeframe_key(16388) == "H4"
    assert timeframe_key(16408) == "D1"
