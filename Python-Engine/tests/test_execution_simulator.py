from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.execution.execution_simulator import ExecutionBucket, ExecutionModel, simulate_order

def test_execution_simulator_is_deterministic():
    b = ExecutionBucket("EURUSD", "London", "normal", "normal")
    m = ExecutionModel(1.2, 0.01, 120.0)
    a = simulate_order(b, m, "abc")
    c = simulate_order(b, m, "abc")
    assert a == c

def test_execution_simulator_non_negative_outputs():
    b = ExecutionBucket("EURUSD", "NY", "wide", "high")
    m = ExecutionModel(2.5, 0.02, 200.0)
    out = simulate_order(b, m, "xyz")
    assert out["slippage_points"] >= 0
    assert out["ack_ms"] >= 0
