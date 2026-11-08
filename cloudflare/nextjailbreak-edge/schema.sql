CREATE TABLE IF NOT EXISTS comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT NOT NULL,
  name TEXT NOT NULL,
  body TEXT NOT NULL,
  ip_hash TEXT NOT NULL,
  approved INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_comments_slug_approved_id
ON comments(slug, approved, id);

CREATE INDEX IF NOT EXISTS idx_comments_ip_created
ON comments(ip_hash, created_at);

-- Location testing is opt-in; records are private bearer-capability results.
-- Cleanup occurs on access and through the scheduled hourly job.
CREATE TABLE IF NOT EXISTS location_tests (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  accuracy_m REAL NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_location_tests_expiry ON location_tests(expires_at);
