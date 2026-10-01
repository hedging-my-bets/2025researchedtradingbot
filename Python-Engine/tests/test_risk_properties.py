from pathlib import Path
import random
import sys

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from risk.policy_reference import drawdown_state, final_size_multiplier

def test_final_size_is_monotone_when_any_cap_tightens():
    rng = random.Random(42)
    for _ in range(1000):
        caps = [rng.random() for _ in range(6)]
        base = final_size_multiplier(*caps)
        idx = rng.randrange(len(caps))
        tighter = caps.copy()
        tighter[idx] *= 0.5
        assert final_size_multiplier(*tighter) <= base + 1e-12

def test_drawdown_boundaries():
    assert drawdown_state(0.0,0.0,0.0)[0] == "NORMAL"
    assert drawdown_state(0.021,0.0,0.0)[0] == "SOFT_HALT"
    assert drawdown_state(0.03,0.0,0.0)[0] == "HARD_HALT"
    assert drawdown_state(0.0,0.07,0.0)[0] == "HARD_HALT"
    assert drawdown_state(0.0,0.0,0.12)[0] == "HARD_HALT"
