def handle_missing_cross_asset(df: pd.DataFrame, cols: list[str], fill: float = 0.0) -> pd.DataFrame:
    for c in cols:
        if c not in df.columns:
            df[c] = fill
        else:
            df[c] = df[c].fillna(method="ffill", limit=5).fillna(fill)
    return df