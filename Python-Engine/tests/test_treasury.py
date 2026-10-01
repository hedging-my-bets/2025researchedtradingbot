from pathlib import Path
import sys

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from treasury.cost_model import CostEstimate, adjusted_target_rr, net_expected_value

def test_costs_reduce_ev_and_rr():
    c = CostEstimate(spread=0.02, commission=0.01, swap_or_funding=0.005, slippage=0.015)
    assert abs(c.total - 0.05) < 1e-12
    assert abs(net_expected_value(0.20, c) - 0.15) < 1e-12
    assert adjusted_target_rr(2.0, 0.1) == 1.9
