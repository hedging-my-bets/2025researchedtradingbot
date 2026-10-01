from pathlib import Path
import sys

SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from tca.nightly_tca import summarize

def test_tca_reports_latency_rejects_retries_and_costs():
    rows = [
        {"event":"broker_ack","ts":1700000000,"symbol":"EURUSD","retcode":10009,
         "intended_price":1.1000,"fill_price":1.1001,"latency_ms":100,"attempt":1},
        {"event":"broker_ack","ts":1700000001,"symbol":"EURUSD","retcode":10020,
         "intended_price":1.1000,"fill_price":0,"latency_ms":300,"attempt":2},
        {"event":"trade_close","ts":1700000100,"symbol":"EURUSD","gross_profit":10,
         "commission":-1,"swap":-0.5,"net_pnl":8.5},
    ]
    report = summarize(rows)
    key = next(iter(report["execution"]))
    assert report["execution"][key]["orders"] == 2
    assert report["execution"][key]["reject_rate"] == 0.5
    assert report["execution"][key]["p95_attempt"] > 1
    assert report["closes"]["EURUSD"]["net_pnl"] == 8.5
    assert report["closes"]["EURUSD"]["reported_costs"] == 1.5
