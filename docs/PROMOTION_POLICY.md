# FXSuite Ω Promotion Policy

No model, execution policy, sizing policy or hedge policy is promoted because it is "better in backtest."

A candidate is eligible only when the machine-readable promotion gate passes all required fields.

Current gate interpretation:

- at least 6 rolling weeks
- candidate PSR probability at least baseline + 0.15 absolute
- required uplift in at least 3 of 4 predefined regimes
- ECE <= 0.03
- Brier <= 0.18
- conformal coverage >= 90%
- conformal width <= configured policy
- inference p95 <= 400 ms
- broker acknowledgement p95 <= 250 ms
- reject rate <= 1%
- simulated/live median execution error <= 10%
- observed/simulated maximum DD stays within 3% day / 7% week / 12% peak policy

The gate is intentionally conservative and does not auto-deploy. A passing result makes a candidate **eligible for review**, not automatically live.
