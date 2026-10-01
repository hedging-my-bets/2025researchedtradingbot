from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

@dataclass(frozen=True)
class TimeSyncStatus:
    offset_ms: int
    within_policy: bool
    policy_ms: int = 300

def compare_epoch_ms(remote_or_mt5_epoch_ms: int, local_epoch_ms: int | None = None, policy_ms: int = 300) -> TimeSyncStatus:
    if local_epoch_ms is None:
        local_epoch_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    offset = int(remote_or_mt5_epoch_ms) - int(local_epoch_ms)
    return TimeSyncStatus(offset_ms=offset, within_policy=abs(offset) <= policy_ms, policy_ms=policy_ms)
