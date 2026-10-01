from pathlib import Path
import sys
import numpy as np

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from research.walk_forward import purged_walk_forward
from research.metrics import probabilistic_sharpe_ratio
from governance.promotion_gate import PromotionMetrics, evaluate_promotion

def test_walk_forward_has_embargo_and_no_overlap():
    folds = purged_walk_forward(
        1000, train_size=400, valid_size=100, test_size=100, embargo=10, step=100
    )
    assert folds
    for f in folds:
        assert f.valid_start - f.train_end == 10
        assert f.test_start - f.valid_end == 10
        assert f.train_end <= f.valid_start <= f.valid_end <= f.test_start <= f.test_end

def test_psr_is_high_for_positive_stable_returns():
    r = np.array([0.01, 0.012, 0.009, 0.011, 0.0105] * 50)
    assert probabilistic_sharpe_ratio(r) > 0.95

def test_promotion_gate_passes_only_when_every_gate_passes():
    good = PromotionMetrics(
        rolling_weeks=6, psr_candidate=0.80, psr_baseline=0.60,
        regimes_with_required_lift=3, ece=0.02, brier=0.16,
        conformal_coverage=0.92, conformal_width=0.18, conformal_max_width=0.20,
        inference_p95_ms=300, broker_ack_p95_ms=180, reject_rate=0.005,
        parity_median_error_pct=0.08, max_day_dd=0.02, max_week_dd=0.05, max_peak_dd=0.09,
    )
    assert evaluate_promotion(good).eligible
    bad = PromotionMetrics(**{**good.__dict__, "reject_rate": 0.02})
    decision = evaluate_promotion(bad)
    assert not decision.eligible
    assert not decision.checks["reject_rate"]
