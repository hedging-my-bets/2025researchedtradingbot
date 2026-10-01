from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True)
class WalkForwardFold:
    train_start: int
    train_end: int
    valid_start: int
    valid_end: int
    test_start: int
    test_end: int

def purged_walk_forward(
    n_samples: int,
    *,
    train_size: int,
    valid_size: int,
    test_size: int,
    embargo: int = 0,
    step: int | None = None,
):
    if min(n_samples, train_size, valid_size, test_size) <= 0 or embargo < 0:
        raise ValueError("invalid fold dimensions")
    if step is None:
        step = test_size
    if step <= 0:
        raise ValueError("step must be positive")

    start = 0
    folds = []
    while True:
        train_start = start
        train_end = train_start + train_size
        valid_start = train_end + embargo
        valid_end = valid_start + valid_size
        test_start = valid_end + embargo
        test_end = test_start + test_size
        if test_end > n_samples:
            break
        folds.append(WalkForwardFold(
            train_start, train_end, valid_start, valid_end, test_start, test_end
        ))
        start += step
    return folds
