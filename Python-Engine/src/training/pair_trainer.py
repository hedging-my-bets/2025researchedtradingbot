from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import yaml

SRC = Path(__file__).resolve().parents[1]
ROOT = SRC.parent
REPO_ROOT = ROOT.parent
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from calibration.calibrators import CalibrationArtifact, CalibrationSelector, calibration_metrics
from ml_pipeline.model_registry import build_manifest, sha256_file, write_manifest_atomic
from research.metrics import probabilistic_sharpe_ratio
from research.walk_forward import purged_walk_forward
from training.dataset_contract import load_training_frame
from training.model_card import render_model_card

def _candidate_id(symbol: str, timeframe: str, dataset_hash: str, features_hash: str) -> str:
    seed = f"{symbol}|{timeframe}|{dataset_hash}|{features_hash}|lightgbm-v1"
    return f"{symbol}-{timeframe}-{hashlib.sha256(seed.encode()).hexdigest()[:12]}"

def _export_onnx(model, feature_count: int, output_path: Path) -> None:
    try:
        import onnxmltools
        from onnxmltools.convert.common.data_types import FloatTensorType
    except ImportError as exc:
        raise RuntimeError("ONNX export dependencies are missing; install requirements-train.txt") from exc

    onnx_model = onnxmltools.convert_lightgbm(
        model.booster_,
        initial_types=[("input", FloatTensorType([None, feature_count]))],
        target_opset=15,
    )
    output_path.write_bytes(onnx_model.SerializeToString())

def train_candidate(
    csv_path: Path,
    *,
    symbol: str,
    timeframe: str,
    out_dir: Path,
    train_size: int,
    valid_size: int,
    test_size: int,
    embargo: int,
) -> dict:
    try:
        import lightgbm as lgb
    except ImportError as exc:
        raise RuntimeError("LightGBM is required; install requirements-train.txt") from exc

    features_path = ROOT / "configs" / "features.yaml"
    scaler_path = ROOT / "configs" / "scaler.json"
    feature_spec = yaml.safe_load(features_path.read_text())
    feature_names = [x["name"] for x in feature_spec["meta_features"]]

    tf = load_training_frame(csv_path, feature_names=feature_names)
    df = tf.frame
    folds = purged_walk_forward(
        len(df),
        train_size=train_size,
        valid_size=valid_size,
        test_size=test_size,
        embargo=embargo,
        step=test_size,
    )
    if len(folds) < 3:
        raise ValueError("at least three walk-forward folds are required")

    oof_p = []
    oof_y = []
    oof_r = []

    params = dict(
        n_estimators=800,
        learning_rate=0.03,
        num_leaves=31,
        min_child_samples=50,
        subsample=0.90,
        colsample_bytree=0.90,
        reg_lambda=1.0,
        random_state=42,
        n_jobs=-1,
    )

    for fold in folds:
        train = df.iloc[fold.train_start:fold.train_end]
        valid = df.iloc[fold.valid_start:fold.valid_end]
        test = df.iloc[fold.test_start:fold.test_end]

        model = lgb.LGBMClassifier(**params)
        model.fit(
            train[feature_names],
            train[tf.label_col].astype(int),
            eval_set=[(valid[feature_names], valid[tf.label_col].astype(int))],
            callbacks=[lgb.early_stopping(60, verbose=False)],
        )
        p = model.predict_proba(test[feature_names])[:, 1]
        oof_p.extend(p.tolist())
        oof_y.extend(test[tf.label_col].astype(int).tolist())
        if tf.return_col:
            oof_r.extend(test[tf.return_col].astype(float).tolist())

    oof_p = np.asarray(oof_p, dtype=float)
    oof_y = np.asarray(oof_y, dtype=float)
    if oof_p.size < 100:
        raise ValueError("insufficient out-of-fold predictions")

    cut = max(50, int(oof_p.size * 0.65))
    if oof_p.size - cut < 30:
        cut = oof_p.size // 2
    selector = CalibrationSelector()
    calibration = selector.fit_select(
        oof_p[:cut], oof_y[:cut], oof_p[cut:], oof_y[cut:]
    )

    calibration_payload = {
        "calibrator_id": "pending",
        **calibration,
        "status": "candidate",
    }
    artifact = CalibrationArtifact(calibration_payload)
    p_cal = np.asarray([artifact.transform(float(p))[0] for p in oof_p], dtype=float)

    raw_metrics = calibration_metrics(oof_y, oof_p)
    calibrated_metrics = calibration_metrics(oof_y, p_cal)

    dataset_hash = sha256_file(csv_path)
    features_hash = sha256_file(features_path)
    model_id = _candidate_id(symbol, timeframe, dataset_hash, features_hash)
    calibration_payload["calibrator_id"] = f"{model_id}-cal"

    out_dir.mkdir(parents=True, exist_ok=True)
    model_path = out_dir / "meta_labeler.onnx"
    calibration_path = out_dir / "calibration.json"
    report_path = out_dir / "research_report.json"
    card_path = out_dir / "MODEL_CARD.md"
    manifest_path = out_dir / "manifest.json"

    final_model = lgb.LGBMClassifier(**params)
    final_model.fit(df[feature_names], df[tf.label_col].astype(int))
    _export_onnx(final_model, len(feature_names), model_path)
    calibration_path.write_text(json.dumps(calibration_payload, sort_keys=True, indent=2) + "\n")

    report = {
        "model_id": model_id,
        "symbol": symbol,
        "timeframe": timeframe,
        "folds": len(folds),
        "rows": len(df),
        "raw_metrics": raw_metrics,
        "calibrated_metrics": calibrated_metrics,
        "conformal": calibration["conformal"],
        "psr_oof_returns": probabilistic_sharpe_ratio(oof_r) if oof_r else None,
        "note": "Research candidate only; no automatic live promotion.",
    }
    report_path.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")

    manifest = build_manifest(
        model_id=model_id,
        symbol=symbol,
        timeframe=timeframe,
        dataset_path=csv_path,
        features_path=features_path,
        scaler_path=scaler_path,
        model_path=model_path,
        calibration_path=calibration_path,
        cv_summary={"folds": len(folds), "embargo": embargo},
        metrics=calibrated_metrics,
    )
    write_manifest_atomic(manifest, manifest_path)

    hashes = {
        "dataset": manifest.dataset_hash,
        "features": manifest.features_hash,
        "scaler": manifest.scaler_hash,
        "model": manifest.model_hash,
        "calibration": manifest.calibration_hash,
    }
    card_path.write_text(render_model_card(
        model_id=model_id,
        symbol=symbol,
        timeframe=timeframe,
        dataset_rows=len(df),
        dataset_start=str(df[tf.timestamp_col].iloc[0]),
        dataset_end=str(df[tf.timestamp_col].iloc[-1]),
        folds=len(folds),
        raw_metrics=raw_metrics,
        calibrated_metrics=calibrated_metrics,
        conformal=calibration["conformal"],
        hashes=hashes,
        notes=[
            "Labels must represent profitability net of execution costs.",
            "Final model is trained after walk-forward evaluation; live eligibility is separate.",
            "Pair/timeframe model must be deployed with matching feature/scaler/calibration hashes.",
        ],
    ))

    return report

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--csv", required=True, type=Path)
    p.add_argument("--symbol", required=True)
    p.add_argument("--timeframe", required=True)
    p.add_argument("--out-dir", required=True, type=Path)
    p.add_argument("--train-size", type=int, required=True)
    p.add_argument("--valid-size", type=int, required=True)
    p.add_argument("--test-size", type=int, required=True)
    p.add_argument("--embargo", type=int, default=5)
    args = p.parse_args()

    report = train_candidate(
        args.csv,
        symbol=args.symbol,
        timeframe=args.timeframe,
        out_dir=args.out_dir,
        train_size=args.train_size,
        valid_size=args.valid_size,
        test_size=args.test_size,
        embargo=args.embargo,
    )
    print(json.dumps(report, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
