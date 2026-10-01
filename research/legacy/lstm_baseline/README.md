# Legacy LSTM baseline

This directory preserves the useful research ideas from `Forex_trading_bot` without promoting its production/security design.

Retained ideas:
- chronological train/validation split
- lag features
- RSI and Bollinger-style features
- multi-step forecasting as an **ablation baseline only**

Not retained:
- hard-coded credentials
- public H5 artifact as a production model
- recursive price forecasts as trading signals
- deployment assumptions from the 2023 code

Any future LSTM result must use the same execution-aligned labels, walk-forward folds, costs and evaluation gates as the main research pipeline.
