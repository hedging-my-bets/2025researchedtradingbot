from __future__ import annotations

def render_model_card(
    *,
    model_id: str,
    symbol: str,
    timeframe: str,
    dataset_rows: int,
    dataset_start: str,
    dataset_end: str,
    folds: int,
    raw_metrics: dict,
    calibrated_metrics: dict,
    conformal: dict,
    hashes: dict,
    notes: list[str],
) -> str:
    def fmt(d):
        return "\n".join(f"- **{k}**: {v}" for k, v in d.items())

    note_text = "\n".join(f"- {n}" for n in notes) or "- none"
    return f"""# Model Card — {model_id}

## Scope
- **Symbol**: {symbol}
- **Timeframe**: {timeframe}
- **Rows**: {dataset_rows}
- **Data start**: {dataset_start}
- **Data end**: {dataset_end}
- **Purged walk-forward folds**: {folds}

## Raw probabilistic metrics
{fmt(raw_metrics)}

## Calibrated probabilistic metrics
{fmt(calibrated_metrics)}

## Conformal
{fmt(conformal)}

## Immutable hashes
{fmt(hashes)}

## Promotion status
This artifact is a **candidate**, not an automatically promoted live model. It must pass the repository promotion gate and separate operational review.

## Notes / limitations
{note_text}
"""
