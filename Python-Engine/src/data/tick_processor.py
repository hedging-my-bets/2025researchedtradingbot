import pandas as pd, numpy as np

class TickCleaner:
    def detect_and_fix(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df[(df["ask"]>0) & (df["bid"]>0) & (df["ask"]>df["bid"])]
        mid = (df["ask"]+df["bid"])/2.0
        r = np.log(mid).diff()
        mu = r.rolling(1000, min_periods=100).mean()
        sd = r.rolling(1000, min_periods=100).std()
        z = (r - mu) / (sd + 1e-12)
        df = df[(z.abs()<8) | z.isna()]
        # drop weekends except Sunday 21:00 UTC+
        idx = df.index
        keep = (idx.dayofweek<=4) | ((idx.dayofweek==6) & (idx.hour>=21))
        return df[keep]

def tag_rollover(df: pd.DataFrame, tz="America/New_York") -> pd.DataFrame:
    local = df.index.tz_convert(tz)
    df["rollover_flag"] = ((local.hour==17) & (local.minute<30)).astype("int8")
    return df