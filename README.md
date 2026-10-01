# FXSuite Ω

Institutional-style MT5 + Python FX research/execution platform under active consolidation.

## Canonical architecture

- **MT5/MQL5** — orchestration, broker execution, position/risk controls, news/regime guards and NDJSON audit events.
- **Python Engine** — model inference, feature contracts, monitoring, research, TCA and execution simulation.
- **Infrastructure** — durable model/prediction/order/trade data schema.
- **Research** — legacy donor ideas are isolated from production code.

## Source consolidation

This repository is the canonical successor to:
- `hedging-my-bets/2025researchedtradingbot`
- useful CI ideas from `hedging-my-bets/2025_trading_bot`
- selected research baselines from `hedging-my-bets/Forex_trading_bot`

See `docs/GAP_ANALYSIS.md` and `docs/OMEGA_ROADMAP.md`.

## Safety defaults

- live trading defaults to **off**
- Omega sizing defaults to **off**
- expanded 3/7/12 drawdown policy defaults to **off**
- ATR trailing defaults to **off**
- unavailable production model is fail-closed unless an explicit stub-development environment variable is set

## Current validation state

Python contract tests and dependency checks run in GitHub Actions.

MQL source has **not** been verified as 0 errors / 0 warnings by MetaEditor in this repository workflow yet. That claim must not be made until a real Windows/MetaEditor compile completes.

## Promotion path

`unit -> integration -> historical replay -> shadow -> paper -> tiny live -> measured scale`

This repository is experimental trading software. Performance thresholds in code or docs are targets, not evidence of achieved returns.
