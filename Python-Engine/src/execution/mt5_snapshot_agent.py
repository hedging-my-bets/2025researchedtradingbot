from __future__ import annotations

import os
import sys
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path

import numpy as np
import pandas as pd
import MetaTrader5 as mt5

ENGINE_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = ENGINE_ROOT.parent
FILES_DIR = REPO_ROOT / "MT5-Platform" / "MQL5" / "Files"
DATA_DIR = ENGINE_ROOT / "src" / "data"
if str(DATA_DIR) not in sys.path:
    sys.path.insert(0, str(DATA_DIR))

from news.calendar_adapter import normalize_calendar_csv, normalize_calendar_frame, write_calendar_status

FILES_DIR.mkdir(parents=True, exist_ok=True)

MAPPING = {
    "DXY": {"symbol": "DXY"},
    "SPX": {"symbol": "US500"},
    "GOLD": {"symbol": "XAUUSD"},
    "OIL": {"symbol": "USOIL"},
    "UST2Y": {"symbol": "US02Y"},
    "FX": ["EURUSD","GBPUSD","USDJPY","AUDUSD","USDCAD","USDCHF","NZDUSD"],
}

def init_mt5():
    if not mt5.initialize():
        raise RuntimeError(f"MT5 initialize failed: {mt5.last_error()}")

def rates(symbol: str, timeframe=mt5.TIMEFRAME_M1, n=90):
    r = mt5.copy_rates_from_pos(symbol, timeframe, 0, n)
    if r is None:
        raise RuntimeError(f"copy_rates_from_pos failed for {symbol}: {mt5.last_error()}")
    df = pd.DataFrame(r)
    df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
    return df.set_index("time")

def _previous_cross_snapshot():
    p = FILES_DIR / "cross_snapshot.csv"
    if not p.exists():
        return {}
    try:
        return pd.read_csv(p).iloc[0].to_dict()
    except Exception:
        return {}

def write_cross_snapshot():
    out = {
        "dxy_ret_60m": 0.0,
        "spx_ret_60m": 0.0,
        "gold_ret_60m": 0.0,
        "oil_ret_60m": 0.0,
        "ust2y_change_bps_60m": 0.0,
    }
    previous = _previous_cross_snapshot()
    out.update({k: previous[k] for k in out if k in previous and pd.notna(previous[k])})

    def logret_60m(sym):
        df = rates(sym, mt5.TIMEFRAME_M5, 13)
        return float(np.log(df["close"].iloc[-1] / df["close"].iloc[0]))

    sources = [
        ("dxy_ret_60m", "DXY"),
        ("spx_ret_60m", "SPX"),
        ("gold_ret_60m", "GOLD"),
        ("oil_ret_60m", "OIL"),
    ]
    for key, mapping_key in sources:
        sym = MAPPING[mapping_key]["symbol"]
        if not sym:
            continue
        try:
            out[key] = logret_60m(sym)
        except Exception:
            pass

    sym = MAPPING["UST2Y"]["symbol"]
    if sym:
        try:
            df = rates(sym, mt5.TIMEFRAME_M5, 13)
            out["ust2y_change_bps_60m"] = float((df["close"].iloc[-1] - df["close"].iloc[0]) * 100.0)
        except Exception:
            pass

    pd.DataFrame([out]).to_csv(FILES_DIR / "cross_snapshot.csv", index=False)
    return out

def write_spread_percentiles(lookback_days=60):
    rows = []
    for sym in MAPPING["FX"]:
        try:
            n = 24 * 60 * lookback_days
            df = rates(sym, mt5.TIMEFRAME_M1, n)
            info = mt5.symbol_info(sym)
            if info is None:
                continue
            pip = info.point * 10.0 if info.digits in (3,5) else info.point
            spr_pips = df["spread"] * info.point / pip
            cur = float(spr_pips.iloc[-1])
            rows.append({"symbol": sym, "pctl": round(float((spr_pips <= cur).mean() * 100.0), 2)})
        except Exception:
            continue
    pd.DataFrame(rows).to_csv(FILES_DIR / "spread_percentiles.csv", index=False)

def sync_slow_factors():
    src = DATA_DIR / "slow" / "slow_factors_latest.csv"
    if src.exists():
        pd.read_csv(src).to_csv(FILES_DIR / "slow_factors.csv", index=False)

def sync_calendar():
    src = DATA_DIR / "news" / "calendar.csv"
    if src.exists():
        frame = pd.read_csv(src)
        normalized = normalize_calendar_frame(frame)
        normalize_calendar_csv(src, FILES_DIR / "calendar.csv")
        write_calendar_status(normalized, FILES_DIR / "news_status.csv")

def main_loop():
    init_mt5()
    last_spread_update = datetime.min.replace(tzinfo=timezone.utc)
    last_slow = datetime.min.replace(tzinfo=timezone.utc)
    last_cal = datetime.min.replace(tzinfo=timezone.utc)

    while True:
        now = datetime.now(timezone.utc)
        write_cross_snapshot()

        if now - last_spread_update > timedelta(minutes=30):
            write_spread_percentiles()
            last_spread_update = now

        slow = DATA_DIR / "slow" / "slow_factors_latest.csv"
        if slow.exists():
            mtime = datetime.fromtimestamp(os.path.getmtime(slow), tz=timezone.utc)
            if mtime > last_slow:
                sync_slow_factors()
                last_slow = mtime

        cal = DATA_DIR / "news" / "calendar.csv"
        if cal.exists():
            mtime = datetime.fromtimestamp(os.path.getmtime(cal), tz=timezone.utc)
            if mtime > last_cal:
                sync_calendar()
                last_cal = mtime

        time.sleep(max(1, 60 - datetime.now(timezone.utc).second))

if __name__ == "__main__":
    main_loop()
