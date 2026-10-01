from pathlib import Path
import sys

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from ml_pipeline.model_registry import build_manifest, write_manifest_atomic

def test_manifest_hashes_and_atomic_write(tmp_path):
    files = {}
    for name in ["dataset", "features", "scaler", "model", "calibration"]:
        path = tmp_path / f"{name}.bin"
        path.write_bytes((name + "-content").encode())
        files[name] = path

    manifest = build_manifest(
        model_id="m1", symbol="EURUSD", timeframe="M15",
        dataset_path=files["dataset"], features_path=files["features"],
        scaler_path=files["scaler"], model_path=files["model"],
        calibration_path=files["calibration"], cv_summary={"folds": 5},
        metrics={"ece": 0.02, "brier": 0.17},
    )
    assert len(manifest.dataset_hash) == 64
    out = tmp_path / "registry" / "manifest.json"
    write_manifest_atomic(manifest, out)
    assert out.exists()
    assert '"model_id": "m1"' in out.read_text()
