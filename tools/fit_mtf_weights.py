from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "Python-Engine" / "src"
sys.path.insert(0, str(SRC))

from ml_pipeline.mtf_blender import fit_group_weights, news_bucket

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--csv", required=True, type=Path)
    p.add_argument("--out", required=True, type=Path)
    args = p.parse_args()

    df = pd.read_csv(args.csv)
    required = {"p_m15","p_h1","p_h4","p_d1","y","regime","minutes_to_news"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"missing columns: {sorted(missing)}")

    groups = {}
    for (regime, bucket), g in df.assign(
        news_bucket=df["minutes_to_news"].map(news_bucket)
    ).groupby(["regime","news_bucket"]):
        if len(g) < 50:
            continue
        groups[f"{int(regime)}:{bucket}"] = fit_group_weights(
            g[["p_m15","p_h1","p_h4","p_d1"]].to_numpy(),
            g["y"].to_numpy(),
        )

    payload = {
        "status": "fitted-candidate",
        "default_weights": [0.55,0.20,0.15,0.10],
        "groups": groups,
        "policy": {
            "coherence_warn": 0.67,
            "coherence_block": 0.34,
            "threshold_add_warn": 0.03,
            "threshold_add_block": 0.08
        }
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(args.out)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
