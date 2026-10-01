# FXSuite Ω Operator Runbook

## Default state
Live trading is disabled by default. Omega sizing, expanded drawdown policy, conformal blocking, strict news health and rollover blocking are explicit controls.

## Before paper/shadow
1. GitHub quality checks must pass.
2. Compile the MQL controller in real MetaEditor and record errors/warnings.
3. Start inference service and verify `/health`.
4. Verify feature/scaler/calibration hashes.
5. Start MT5 snapshot/calendar synchronizer.
6. Verify `sync_status.json` reports clock offset within 300 ms.
7. Verify normalized `calendar.csv` and `news_status.csv` are being refreshed.
8. Run nightly TCA and inspect rejects, p95 acknowledgements and slippage.

## Before tiny live
1. Promotion review is separate from model training.
2. Create/verify the current release fingerprint.
3. Arm the exact current fingerprint:
   `python tools/arm_live.py --phrase "ARM LIVE FXSUITE"`
4. Verify it:
   `python tools/verify_live_approval.py`
5. Any tracked strategy/risk/execution/config change invalidates that approval.
6. Enable live trading only in the MT5 instance intended for the controlled trial.

## Kill / halt
- Set `InpEnableTrades=false` for operator halt.
- Hard DD state blocks new entries.
- Strict news mode blocks on stale/unhealthy calendar feed.
- Rollover guard blocks the configured rollover window when enabled.

## Evidence
Do not label any threshold PROVEN until live/shadow evidence exists. Keep MetaEditor compile evidence, TCA reports, calibration reports, model manifests and promotion decisions with the release.
