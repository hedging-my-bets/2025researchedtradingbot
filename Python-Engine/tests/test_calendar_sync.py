from pathlib import Path
import sys
import pandas as pd

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))
sys.path.insert(0, str(SRC / "data"))

from data.news.calendar_adapter import normalize_calendar_frame, write_calendar_status
from execution.time_sync import compare_epoch_ms

def test_calendar_normalizes_to_mt5_schema():
    df = pd.DataFrame({
        "event_time_iso":["2030-01-01T12:00:00Z","2030-01-01T13:00:00Z"],
        "currency":["usd","EUR"],
        "importance":[3,2],
        "event_name":["A","B"],
    })
    out = normalize_calendar_frame(df)
    assert list(out.columns) == ["utc_ts","impact","currency","title"]
    assert out.iloc[0]["impact"] == "HIGH"
    assert out.iloc[1]["impact"] == "MEDIUM"
    assert out.iloc[0]["currency"] == "USD"
    assert int(out.iloc[0]["utc_ts"]) > 0

def test_time_sync_policy_300ms():
    assert compare_epoch_ms(1000, 800, 300).within_policy
    assert not compare_epoch_ms(1201, 800, 300).within_policy

def test_calendar_status_is_written(tmp_path):
    df = pd.DataFrame({
        "event_time_iso":["2030-01-01T12:00:00Z"],
        "currency":["USD"],
        "importance":[3],
        "event_name":["A"],
    })
    normalized = normalize_calendar_frame(df)
    out = tmp_path / "news_status.csv"
    write_calendar_status(normalized, out, pd.Timestamp("2029-12-31T00:00:00Z"))
    status = pd.read_csv(out).iloc[0]
    assert int(status["event_count"]) == 1
    assert int(status["latest_event_utc"]) > int(status["generated_utc"])
