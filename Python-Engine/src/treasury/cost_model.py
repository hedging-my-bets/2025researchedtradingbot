from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True)
class CostEstimate:
    spread: float
    commission: float
    swap_or_funding: float
    slippage: float

    @property
    def total(self) -> float:
        return self.spread + self.commission + self.swap_or_funding + self.slippage

def net_expected_value(gross_ev: float, costs: CostEstimate) -> float:
    return gross_ev - costs.total

def adjusted_target_rr(gross_target_rr: float, expected_cost_r: float) -> float:
    return max(0.0, gross_target_rr - expected_cost_r)
