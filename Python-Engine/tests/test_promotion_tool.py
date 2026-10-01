from pathlib import Path
import json
import sys
import pytest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
SRC = ROOT / "Python-Engine" / "src"
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(SRC))

import promote_candidate
from ml_pipeline.model_registry import sha256_file

def _candidate(tmp_path, symbol="EURUSD", timeframe="M15"):
    d = tmp_path / "candidate"
    d.mkdir()
    model = d / "meta_labeler.onnx"
    calibration = d / "calibration.json"
    model.write_bytes(b"onnx-placeholder")
    calibration.write_text('{"method":"identity","calibrator_id":"test"}')
    manifest = {
        "model_id":"test-model",
        "symbol":symbol,
        "timeframe":timeframe,
        "features_hash":sha256_file(promote_candidate.FEATURES),
        "scaler_hash":sha256_file(promote_candidate.SCALER),
        "model_hash":sha256_file(model),
        "calibration_hash":sha256_file(calibration),
    }
    (d / "manifest.json").write_text(json.dumps(manifest))
    return d

def test_ineligible_decision_is_blocked(tmp_path):
    candidate = _candidate(tmp_path)
    decision = tmp_path / "decision.json"
    decision.write_text('{"eligible":false}')
    with pytest.raises(RuntimeError):
        promote_candidate.promote(candidate, decision, live_root=tmp_path / "live")

def test_eligible_candidate_promotes_to_exact_route(tmp_path):
    candidate = _candidate(tmp_path)
    decision = tmp_path / "decision.json"
    decision.write_text('{"eligible":true}')
    target = promote_candidate.promote(
        candidate, decision, live_root=tmp_path / "live"
    )
    assert target == tmp_path / "live" / "EURUSD" / "M15"
    assert (target / "manifest.json").exists()
    receipt = json.loads((target / "PROMOTION_RECEIPT.json").read_text())
    assert receipt["eligible"] is True
    assert receipt["model_id"] == "test-model"
