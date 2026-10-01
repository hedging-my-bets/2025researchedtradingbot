from __future__ import annotations
import numpy as np
import pandas as pd

def chronological_split(df: pd.DataFrame, train_fraction: float = 0.8):
    if not 0.0 < train_fraction < 1.0:
        raise ValueError("train_fraction must be between 0 and 1")
    cut = int(len(df) * train_fraction)
    return df.iloc[:cut].copy(), df.iloc[cut:].copy()

def add_lags(df: pd.DataFrame, column: str = "close", n: int = 20) -> pd.DataFrame:
    out = df.copy()
    for lag in range(1, n + 1):
        out[f"{column}_lag_{lag}"] = out[column].shift(lag)
    return out.dropna().copy()

def add_rsi(df: pd.DataFrame, column: str = "close", period: int = 14) -> pd.DataFrame:
    out = df.copy()
    delta = out[column].diff()
    up = delta.clip(lower=0.0)
    down = (-delta).clip(lower=0.0)
    avg_up = up.ewm(alpha=1 / period, adjust=False, min_periods=period).mean()
    avg_down = down.ewm(alpha=1 / period, adjust=False, min_periods=period).mean()
    rs = avg_up / avg_down.replace(0.0, np.nan)
    out["rsi"] = 100.0 - (100.0 / (1.0 + rs))
    return out

def add_bollinger(df: pd.DataFrame, column: str = "close", period: int = 20, sigma: float = 2.0) -> pd.DataFrame:
    out = df.copy()
    mean = out[column].rolling(period).mean()
    std = out[column].rolling(period).std(ddof=0)
    out["bb_mid"] = mean
    out["bb_upper"] = mean + sigma * std
    out["bb_lower"] = mean - sigma * std
    out["bb_width"] = out["bb_upper"] - out["bb_lower"]
    return out
