# FXSuite Ω — Three-Repository Consolidation Gap Analysis

Canonical repository: `hedging-my-bets/2025researchedtradingbot`

Compared:
- `2025researchedtradingbot`
- `2025_trading_bot`
- `Forex_trading_bot`
- current FXSuite institutional thesis set supplied with the project
- EdgeForge BC operational-safety reference supplied with the project

## Status language

- **IMPLEMENTED** — code exists.
- **TESTED** — automated or replay validation exists and passes.
- **PROVEN** — live evidence satisfies the stated KPI.

Thresholds in configuration do **not** make a KPI proven.

## Consolidation choice

`2025researchedtradingbot` remains canonical because it already contains the best MT5 + Python + monitoring architecture.

`2025_trading_bot` contributes CI/review workflow ideas.

`Forex_trading_bot` is retained only as a legacy research donor for chronological splitting, lagged features, RSI/Bollinger prototypes and an LSTM ablation baseline. Its historical H5 artifact is **not** promoted to production.

## Implemented on omega/consolidate-three-repos

### Core correctness
- fixed MT5/Python correlation field mismatch
- fixed Python repository path assumptions
- corrected MQL5 Bollinger buffer use
- corrected MACD histogram derivation
- removed MQL4-style ATR access
- removed invalid CArrayObj state storage
- corrected position-risk unit math
- risk sizing no longer rounds an under-minimum position upward

### Execution
- bounded retry wrapper with retcode taxonomy
- exponential backoff
- correlation-id idempotency within process lifetime
- broker acknowledgement NDJSON events

### Position management
- BE trigger by equity-profit percentage and/or R
- BE offset includes spread/tick protection
- tick snap
- stops/freeze checks
- no intentional SL widening
- optional ATR trailing
- `sl_change` telemetry

### Risk
- optional day/week/peak drawdown state machine
- soft halt size reduction
- hard halt trade blocking
- corrected portfolio risk heat
- projected margin check
- confidence/Kelly module
- CVaR tracker and lot scaler

### Feature / ML plumbing
- explicit versioned 64-feature contract
- client/server feature-version check
- model-unavailable state is fail-closed unless explicit stub mode is enabled
- PSI monitor uses observed baseline samples rather than fabricated random normals
- Page-Hinkley residual detector
- ECE/Brier/MCE monitoring thresholds

### TCA / telemetry
Current event families include:
- `trade_intent`
- `broker_ack`
- `sl_change`
- `risk_state`
- `hedge_state`
- `calibration_metrics`

Nightly broker-ack TCA summarizer is installed.

## Not yet PROVEN / intentionally not claimed

- MetaEditor 0 errors / 0 warnings
- six-week +15% PSR lift
- ECE <= 0.03 live
- Brier <= 0.18 live
- conformal >= 90% coverage
- inference p95 <= 400ms live
- broker ack p95 <= 250ms live
- reject <= 1% live
- simulator/live slippage parity within +/-10%
- hedge variance reduction >= 20%
- MTF +5% hit-rate improvement
- 99% CI assurance that configured DD thresholds will never be breached

These require executable validation and live/shadow evidence.

## Remaining engineering

1. Real pair-specific model training and artifact registry.
2. Platt + isotonic rolling selector.
3. Conformal calibration by symbol/TF/regime bucket.
4. Full MTF server predictions at M15/H1/H4/D1 with learned weights.
5. Dynamic correlation/beta NetHedge execution.
6. Live broker/economic-calendar ingestion and DST/holiday service.
7. Deterministic execution simulator with session x spread x vol taxonomy.
8. TCA realized-vs-expected RR, hold time, costs, cancel/expire.
9. Cost map for spread, commission, swaps/funding and slippage.
10. Windows MetaEditor CI or local compiler handoff.

## Security

The public legacy `Forex_trading_bot` contains a hard-coded Polygon credential in history/current code. Treat it as compromised and rotate/revoke it. It has not been copied into this branch.

## Deployment rule

New Omega behavior is opt-in. Live trading remains disabled by default. Promotion sequence:

`unit -> integration -> replay -> shadow -> paper -> tiny live -> measured scale`
