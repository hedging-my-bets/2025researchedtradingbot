# Writes the CSVs that MT5 FeatureExtractor reads:
#  - Files/cross_snapshot.csv            (updated every minute)
#  - Files/spread_percentiles.csv        (updated every 30 minutes)
#  - Files/slow_factors.csv              (copied from data/slow/slow_factors_latest.csv daily)
#  - Files/calendar.csv                  (copied from data/news/calendar.csv whenever it changes)
#
# Requires: MetaTrader5 (pip install MetaTrader5), pandas, pytz
# Ensure your MT5 terminal is running & logged in on this machine.
from __future__ import annotations
import os, time
from datetime import datetime, timezone, timedelta
from pathlib import Path
import pandas as pd
import numpy as np
import MetaTrader5 as mt5

ROOT = Path(__file__).resolve().parents[2]
FILES_DIR = ROOT / "MT5-Platform" / "MQL5" / "Files"
DATA_DIR  = ROOT / "src" / "data"

FILES_DIR.mkdir(parents=True, exist_ok=True)

# ---- broker symbol mapping (edit to fit your broker) ----
MAPPING = {
    # cross-asset sources used by FeatureExtractor
    "DXY":   {"symbol": "DXY"},        # e.g. .DXY or USDX; else provide your proxy
    "SPX":   {"symbol": "US500"},      # or SPX500, US500.cash
    "GOLD":  {"symbol": "XAUUSD"},
    "OIL":   {"symbol": "USOIL"},      # or UKOIL/Brent
    "UST2Y": {"symbol": "US02Y"},      # many brokers expose US02Y; else leave blank
    # FX symbols you trade (for spread percentile calc)
    "FX": ["EURUSD","GBPUSD","USDJPY","AUDUSD","USDCAD","USDCHF","NZDUSD"]
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

def write_cross_snapshot():
    # 60m returns / changes
    out = {
        "dxy_ret_60m": 0.0,
        "spx_ret_60m": 0.0,
        "gold_ret_60m": 0.0,
        "oil_ret_60m": 0.0,
        "ust2y_change_bps_60m": 0.0
    }
    def logret_60m(sym):
        df = rates(sym, mt5.TIMEFRAME_M5, 12)  # 12x5m = 60m
        c0, c12 = df["close"].iloc[-1], df["close"].iloc[0]
        return float(np.log(c0 / c12))
    try:
        if (s:=MAPPING["DXY"]["symbol"]):   out["dxy_ret_60m"]  = logret_60m(s)
        if (s:=MAPPING["SPX"]["symbol"]):   out["spx_ret_60m"]  = logret_60m(s)
        if (s:=MAPPING["GOLD"]["symbol"]):  out["gold_ret_60m"] = logret_60m(s)
        if (s:=MAPPING["OIL"]["symbol"]):   out["oil_ret_60m"]  = logret_60m(s)
        if (s:=MAPPING["UST2Y"]["symbol"]):
            df = rates(s, mt5.TIMEFRAME_M5, 12)
            out["ust2y_change_bps_60m"] = float((df["close"].iloc[-1] - df["close"].iloc[0]) * 100.0)
    except Exception as e:
        # Keep previous values if any; otherwise zeros
        pass

    p = FILES_DIR / "cross_snapshot.csv"
    tmp = pd.DataFrame([out])
    tmp.to_csv(p, index=False)
    return out

def write_spread_percentiles(lookback_days=60):
    rows = []
    for sym in MAPPING["FX"]:
        try:
            n = 24*60*lookback_days
            df = rates(sym, mt5.TIMEFRAME_M1, n)
            # 'spread' is in points; convert to pips
            pt = mt5.symbol_info(sym).point
            digits = mt5.symbol_info(sym).digits
            pip = pt*10.0 if digits in (3,5) else pt
            spr_pips = df["spread"] * pt / pip
            # current spread from last bar
            cur = float(spr_pips.iloc[-1])
            # percentile of current vs history
            pctl = float((spr_pips <= cur).mean() * 100.0)
            rows.append({"symbol": sym, "pctl": round(pctl, 2)})
        except Exception:
            continue
    pd.DataFrame(rows).to_csv(FILES_DIR/"spread_percentiles.csv", index=False)

def sync_slow_factors():
    src = DATA_DIR / "slow" / "slow_factors_latest.csv"
    if src.exists():
        df = pd.read_csv(src)
        df.to_csv(FILES_DIR/"slow_factors.csv", index=False)

def sync_calendar():
    src = DATA_DIR / "news" / "calendar.csv"
    if src.exists():
        df = pd.read_csv(src)
        # enforce required columns & ISO times
        df["event_time_iso"] = pd.to_datetime(df["event_time_iso"], utc=True).dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        df[["event_time_iso","currency","importance"]].to_csv(FILES_DIR/"calendar.csv", index=False)

def main_loop():
    init_mt5()
    last_spread_update = datetime.min.replace(tzinfo=timezone.utc)
    last_slow = datetime.min.replace(tzinfo=timezone.utc)
    last_cal  = datetime.min.replace(tzinfo=timezone.utc)

    while True:
        now = datetime.now(timezone.utc)
        write_cross_snapshot()

        if now - last_spread_update > timedelta(minutes=30):
            write_spread_percentiles()
            last_spread_update = now

        # daily syncs (or whenever file changed)
        if (DATA_DIR / "slow" / "slow_factors_latest.csv").exists():
            mtime = datetime.fromtimestamp(os.path.getmtime(DATA_DIR/"slow"/"slow_factors_latest.csv"), tz=timezone.utc)
            if mtime > last_slow:
                sync_slow_factors(); last_slow = mtime

        if (DATA_DIR / "news" / "calendar.csv").exists():
            mtime = datetime.fromtimestamp(os.path.getmtime(DATA_DIR/"news"/"calendar.csv"), tz=timezone.utc)
            if mtime > last_cal:
                sync_calendar(); last_cal = mtime

        # sleep to next minute boundary
        time.sleep(max(1, 60 - datetime.utcnow().second))

if __name__ == "__main__":
    main_loop()