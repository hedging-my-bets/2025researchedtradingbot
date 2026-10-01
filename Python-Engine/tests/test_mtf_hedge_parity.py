from pathlib import Path
import sys
import numpy as np

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from ml_pipeline.mtf_blender import MTFBlender, fit_group_weights
from portfolio.hedge_model import estimate_hedge
from execution.execution_calibration import fit_execution_models, parity_report

def test_mtf_blender_blocks_strong_high_tf_disagreement():
    cfg = {
        "default_weights":[0.55,0.2,0.15,0.1],
        "groups":{},
        "policy":{"coherence_warn":0.67,"coherence_block":0.34,
                  "threshold_add_warn":0.03,"threshold_add_block":0.08},
    }
    result = MTFBlender(cfg).blend([0.70,0.40,0.30,0.20], regime=0, minutes_to_news=300)
    assert result.blocked
    assert result.threshold_add == 0.08

def test_learned_mtf_weights_are_normalized():
    n = 100
    p0 = np.linspace(0.1,0.9,n)
    probs = np.column_stack([p0, np.full(n,0.5), np.full(n,0.5), np.full(n,0.5)])
    y = (p0 > 0.5).astype(float)
    weights = fit_group_weights(probs, y, steps=300, lr=0.05)
    assert abs(sum(weights)-1.0) < 1e-9
    assert all(w >= 0 for w in weights)
    assert weights[0] > max(weights[1:])

def test_hedge_estimator_reduces_variance():
    rng = np.random.default_rng(42)
    h = rng.normal(0,0.01,90)
    p = 0.8*h + rng.normal(0,0.002,90)
    est = estimate_hedge(p,h,max_ratio=1.0)
    assert est.correlation > 0.8
    assert est.hedge_ratio < 0
    assert est.variance_reduction > 0.2

def test_execution_models_and_parity():
    rows = [
        {"event":"broker_ack","ts":1700000000,"symbol":"EURUSD","retcode":10009,
         "intended_price":1.1000,"fill_price":1.1001,"latency_ms":100},
        {"event":"broker_ack","ts":1700000010,"symbol":"EURUSD","retcode":10009,
         "intended_price":1.1000,"fill_price":1.1002,"latency_ms":120},
    ]
    models = fit_execution_models(rows)
    assert models
    report = parity_report({"EURUSD":1.0},{"EURUSD":1.05})
    assert report["all_within_10pct"]
