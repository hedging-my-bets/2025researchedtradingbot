from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from execution.time_sync import compare_epoch_ms

ENGINE_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = ENGINE_ROOT.parent
FILES_DIR = REPO_ROOT / "MT5-Platform" / "MQL5" / "Files"
FEATURES_YAML = ENGINE_ROOT / "configs" / "features.yaml"
SCALER_JSON = ENGINE_ROOT / "configs" / "scaler.json"

@dataclass
class SyncStatus:
    mt5_time_offset_ms: int
    time_within_300ms: bool
    broker_quote_delay_ms: int
    python_calc_delay_ms: int
    features_version: str
    last_heartbeat_utc: str

class DataSynchronizer:
    def __init__(self, out_path: Path = FILES_DIR / "sync_status.json"):
        self.out_path = out_path
        self.mt5_time_offset_ms: Optional[int] = None
        self.time_within_300ms: bool = False
        self.broker_quote_delay_ms: Optional[int] = None
        self.python_calc_delay_ms: Optional[int] = None
        self.features_version = self._hash_files(FEATURES_YAML, SCALER_JSON)

    @staticmethod
    def _hash_files(*paths: Path) -> str:
        h = hashlib.sha256()
        for p in paths:
            h.update(p.read_bytes())
        return h.hexdigest()[:16]

    @staticmethod
    def utcnow_ms() -> int:
        return int(datetime.now(timezone.utc).timestamp() * 1000)

    def compute_offset(self, mt5_now_ms: int) -> int:
        status = compare_epoch_ms(mt5_now_ms, self.utcnow_ms(), policy_ms=300)
        self.mt5_time_offset_ms = status.offset_ms
        self.time_within_300ms = status.within_policy
        return self.mt5_time_offset_ms

    def record_quote_delay(self, tick_utc_ms: int) -> int:
        delay = max(0, self.utcnow_ms() - tick_utc_ms)
        self.broker_quote_delay_ms = delay
        return delay

    def record_feature_latency(self, start_utc_ms: int) -> int:
        delay = max(0, self.utcnow_ms() - start_utc_ms)
        self.python_calc_delay_ms = delay
        return delay

    def write_status(self) -> None:
        status = SyncStatus(
            mt5_time_offset_ms=self.mt5_time_offset_ms or 0,
            time_within_300ms=self.time_within_300ms,
            broker_quote_delay_ms=self.broker_quote_delay_ms or 0,
            python_calc_delay_ms=self.python_calc_delay_ms or 0,
            features_version=self.features_version,
            last_heartbeat_utc=datetime.now(timezone.utc).isoformat(),
        )
        self.out_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.out_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(asdict(status), separators=(",", ":")))
        tmp.replace(self.out_path)
