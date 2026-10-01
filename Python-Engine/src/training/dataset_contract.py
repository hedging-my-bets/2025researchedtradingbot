from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import pandas as pd

@dataclass(frozen=True)
class TrainingFrame:
    frame: pd.DataFrame
    feature_names: list[str]
    label_col: str
    return_col: str | None
    timestamp_col: str

def load_training_frame(
    csv_path: Path,
    *,
    feature_names: list[str],
    label_col: str = "y_net_profitable",
    return_col: str = "realized_r_after_costs",
    timestamp_col: str = "timestamp",
) -> TrainingFrame:
    df = pd.read_csv(csv_path)
    required = [timestamp_col, label_col, *feature_names]
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(f"missing training columns: {missing[:10]}")

    df[timestamp_col] = pd.to_datetime(df[timestamp_col], utc=True, errors="raise")
    df = df.sort_values(timestamp_col, kind="mergesort").reset_index(drop=True)

    if df[timestamp_col].duplicated().any():
        raise ValueError("duplicate timestamps are not allowed")
    if df[feature_names].isna().any().any():
        raise ValueError("feature matrix contains nulls")

    labels = set(df[label_col].astype(int).unique().tolist())
    if not labels <= {0, 1} or not labels:
        raise ValueError("label must be binary 0/1")

    rc = return_col if return_col in df.columns else None
    if rc is not None and df[rc].isna().any():
        raise ValueError("return column contains nulls")

    return TrainingFrame(
        frame=df,
        feature_names=feature_names,
        label_col=label_col,
        return_col=rc,
        timestamp_col=timestamp_col,
    )
