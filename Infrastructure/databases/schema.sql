CREATE TABLE IF NOT EXISTS models (
  model_id TEXT PRIMARY KEY,
  created_utc TIMESTAMP,
  features_hash TEXT,
  scaler_version TEXT,
  auc NUMERIC,
  brier NUMERIC
);

CREATE TABLE IF NOT EXISTS model_manifests (
  model_id TEXT PRIMARY KEY REFERENCES models(model_id),
  symbol TEXT NOT NULL,
  tf TEXT NOT NULL,
  dataset_hash TEXT NOT NULL,
  features_hash TEXT NOT NULL,
  scaler_hash TEXT NOT NULL,
  model_hash TEXT NOT NULL,
  calibration_hash TEXT NOT NULL,
  manifest_json JSONB NOT NULL,
  created_utc TIMESTAMP DEFAULT NOW()
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

CREATE TABLE IF NOT EXISTS calibration_metrics (
  id BIGSERIAL PRIMARY KEY,
  model_id TEXT REFERENCES models(model_id),
  symbol TEXT NOT NULL,
  tf TEXT NOT NULL,
  regime TEXT,
  sample_count INT NOT NULL,
  ece NUMERIC,
  brier NUMERIC,
  mce NUMERIC,
  conformal_coverage NUMERIC,
  conformal_width NUMERIC,
  created_utc TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tca_metrics (
  id BIGSERIAL PRIMARY KEY,
  symbol TEXT NOT NULL,
  session TEXT,
  spread_bucket TEXT,
  vol_bucket TEXT,
  sample_count INT NOT NULL,
  reject_rate NUMERIC,
  ack_p95_ms NUMERIC,
  slippage_median NUMERIC,
  slippage_p95 NUMERIC,
  parity_error_pct NUMERIC,
  created_utc TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS risk_events (
  id BIGSERIAL PRIMARY KEY,
  event_utc TIMESTAMP DEFAULT NOW(),
  state TEXT NOT NULL,
  day_dd NUMERIC,
  week_dd NUMERIC,
  peak_dd NUMERIC,
  size_mult NUMERIC,
  reason TEXT
);
