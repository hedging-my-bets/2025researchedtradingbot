# FXSuite Ω Roadmap

## Gate 0 — Compile and contract correctness
- MetaEditor compile `MASTER_CONTROLLER.mq5`
- target 0 errors / 0 warnings
- Python feature-contract CI green
- inference request round-trip
- no hard-coded credentials

## Gate 1 — Execution / parity
Build deterministic execution simulator using live TCA buckets:
- session
- spread percentile
- volatility regime
- symbol
- retcode/reject class

Promotion target:
- live reject <= 1%
- send to broker acknowledgement p95 <= 250 ms
- simulator median fill/slippage within +/-10% of live buckets

## Gate 2 — Risk / drawdown
- rolling CVaR95 in R
- soft and hard halts
- monotonic lot-sizing property tests
- alert path within 5 seconds

Legacy policy remains available. Omega 3/7/12 policy is explicit opt-in.

## Gate 3 — Position management
- BE+ historical replay
- ATR trail by TF/regime
- no-widening property tests
- broker stops/freeze replay

## Gate 4 — Calibration / MTF
- pair/TF Platt
- local isotonic fallback
- rolling lower-ECE selector
- conformal intervals by regime
- M15/H1/H4/D1 predictions
- learned weights by regime/news distance

Promotion targets:
- ECE <= 0.03
- Brier <= 0.18
- conformal coverage >= 90%
- width below configured policy

## Gate 5 — Hedging / news
- 60-90d signed correlation/beta
- net heat enforcement
- hedge basis-risk accounting
- live calendar, DST, broker holiday and rollover guards

## Gate 6 — Alpha / feature flywheel
- 7-10 years per pair/TF where quality data exists
- execution-aligned labels
- walk-forward validation
- ablations
- drift-triggered retraining
- model cards / hashes

Promotion target:
- live PSR >= baseline +15% over 6 rolling weeks
- improvement present in at least 3/4 predefined regimes

## Gate 7 — Treasury
Feed all-in transaction costs into EV and target selection:
- spread
- commission
- swaps/funding
- slippage

Target:
- >=10% cost/trade reduction without degrading risk-adjusted outcome
