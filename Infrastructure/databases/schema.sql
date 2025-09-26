CREATE TABLE IF NOT EXISTS models (
  model_id TEXT PRIMARY KEY,
  created_utc TIMESTAMP,
  features_hash TEXT,
  scaler_version TEXT,
  auc NUMERIC,
  brier NUMERIC
);

CREATE TABLE IF NOT EXISTS predictions (
  id BIGSERIAL PRIMARY KEY,
  signal_id TEXT,
  symbol TEXT,
  tf TEXT,
  open_time TIMESTAMP,
  feature_vector JSONB,
  p_win NUMERIC,
  model_id TEXT REFERENCES models(model_id),
  created_utc TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
  id BIGSERIAL PRIMARY KEY,
  signal_id TEXT,
  mt5_ticket BIGINT,
  symbol TEXT,
  order_type TEXT,
  intended_price NUMERIC,
  fill_price NUMERIC,
  slippage_reason INT,
  status TEXT,
  created_utc TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS trades (
  id BIGSERIAL PRIMARY KEY,
  mt5_ticket BIGINT,
  symbol TEXT,
  entry_utc TIMESTAMP,
  exit_utc TIMESTAMP,
  size NUMERIC,
  pnl NUMERIC,
  mae NUMERIC,
  mfe NUMERIC
);