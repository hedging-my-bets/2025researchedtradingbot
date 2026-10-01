from __future__ import annotations

from pathlib import Path
import os
import tempfile
import pandas as pd

IMPORTANCE_MAP = {
    0: "LOW",
    1: "LOW",
    2: "MEDIUM",
    3: "HIGH",
}

def normalize_calendar_frame(df: pd.DataFrame) -> pd.DataFrame:
    required = {"event_time_iso", "currency", "importance"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"calendar missing columns: {sorted(missing)}")

    ts = pd.to_datetime(df["event_time_iso"], utc=True, errors="raise")
    imp = df["importance"].astype(int).map(IMPORTANCE_MAP)
    if imp.isna().any():
        raise ValueError("calendar contains unsupported importance value")

    title_col = "event_name" if "event_name" in df.columns else None
    title = df[title_col].astype(str) if title_col else ""

    out = pd.DataFrame({
        "utc_ts": (ts.astype("int64") // 10**9).astype("int64"),
        "impact": imp,
        "currency": df["currency"].astype(str).str.upper(),
        "title": title,
    })
    return out.sort_values("utc_ts", kind="mergesort").reset_index(drop=True)

def normalize_calendar_csv(source: Path, destination: Path) -> None:
    df = pd.read_csv(source)
    out = normalize_calendar_frame(df)
    destination.parent.mkdir(parents=True, exist_ok=True)

    fd, tmp = tempfile.mkstemp(prefix="calendar_", suffix=".csv", dir=str(destination.parent))
    try:
        os.close(fd)
        out.to_csv(tmp, index=False)
        os.replace(tmp, destination)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def calendar_coverage(df: pd.DataFrame, now_utc: pd.Timestamp, forward_hours: int = 168) -> dict:
    normalized = normalize_calendar_frame(df)
    now_s = int(now_utc.timestamp())
    future = normalized[normalized["utc_ts"] >= now_s]
    horizon = normalized[normalized["utc_ts"] <= now_s + forward_hours * 3600]
    return {
        "future_events": int(len(future)),
        "events_in_horizon": int(len(future.merge(horizon, how="inner"))),
        "latest_event_ts": int(normalized["utc_ts"].max()) if len(normalized) else 0,
    }
