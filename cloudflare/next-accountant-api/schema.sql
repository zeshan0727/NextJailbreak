PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS WebMeta (
  Key TEXT PRIMARY KEY,
  Value TEXT NOT NULL DEFAULT '',
  UpdatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS WebAuditLog (
  Id INTEGER PRIMARY KEY AUTOINCREMENT,
  Action TEXT NOT NULL,
  Resource TEXT NOT NULL DEFAULT '',
  ResourceId TEXT NOT NULL DEFAULT '',
  DetailsJson TEXT NOT NULL DEFAULT '',
  CreatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS IX_WebAuditLog_CreatedAt ON WebAuditLog(CreatedAt);

CREATE TABLE IF NOT EXISTS WebFileIndex (
  ObjectKey TEXT PRIMARY KEY,
  OriginalName TEXT NOT NULL DEFAULT '',
  ContentType TEXT NOT NULL DEFAULT 'application/octet-stream',
  SizeBytes INTEGER NOT NULL DEFAULT 0,
  Sha256 TEXT NOT NULL DEFAULT '',
  EntityId INTEGER,
  Category TEXT NOT NULL DEFAULT '',
  RecordType TEXT NOT NULL DEFAULT '',
  RecordId TEXT NOT NULL DEFAULT '',
  UploadedAt TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS IX_WebFileIndex_Record ON WebFileIndex(RecordType, RecordId);

CREATE TABLE IF NOT EXISTS WebMigrationRuns (
  Id INTEGER PRIMARY KEY AUTOINCREMENT,
  SourceName TEXT NOT NULL DEFAULT '',
  SourceSchemaVersion INTEGER NOT NULL DEFAULT 0,
  Status TEXT NOT NULL DEFAULT 'Started',
  TablesImported INTEGER NOT NULL DEFAULT 0,
  RowsImported INTEGER NOT NULL DEFAULT 0,
  FilesImported INTEGER NOT NULL DEFAULT 0,
  Notes TEXT NOT NULL DEFAULT '',
  StartedAt TEXT NOT NULL DEFAULT (datetime('now')),
  CompletedAt TEXT
);


-- Private web read-only access. Tokens are SHA-256 hashes, never plaintext.
-- These are separate Web tables, leaving imported Windows accounting rows unchanged.
CREATE TABLE IF NOT EXISTS WebReadTickets (
  Hash TEXT PRIMARY KEY,
  ExpiresAt INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS IX_WebReadTickets_Expires ON WebReadTickets(ExpiresAt);

CREATE TABLE IF NOT EXISTS WebReadSessions (
  Hash TEXT PRIMARY KEY,
  CreatedAt INTEGER NOT NULL,
  ExpiresAt INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS IX_WebReadSessions_Expires ON WebReadSessions(ExpiresAt);

-- Draft vouchers are isolated from the imported V6 ledger and source vouchers.
-- They never post into PaymentVouchers or ReceiptVouchers automatically.
CREATE TABLE IF NOT EXISTS WebVoucherDrafts (
  Id TEXT PRIMARY KEY,
  EntityId INTEGER NOT NULL,
  Kind TEXT NOT NULL CHECK(Kind IN ('PV','RV')),
  Status TEXT NOT NULL DEFAULT 'DRAFT' CHECK(Status='DRAFT'),
  TransactionDate TEXT NOT NULL,
  Currency TEXT NOT NULL DEFAULT 'QAR',
  AmountMinor INTEGER NOT NULL CHECK(AmountMinor > 0),
  Counterparty TEXT NOT NULL,
  Narrative TEXT NOT NULL DEFAULT '',
  Reference TEXT NOT NULL DEFAULT '',
  AttachmentKey TEXT,
  AttachmentName TEXT,
  AttachmentSha256 TEXT,
  AttachmentBytes INTEGER,
  AttachmentType TEXT,
  CreatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS IX_WebVoucherDrafts_Entity ON WebVoucherDrafts(EntityId,CreatedAt);

CREATE TABLE IF NOT EXISTS WebVoucherDraftAudit (
  Id INTEGER PRIMARY KEY AUTOINCREMENT,
  DraftId TEXT NOT NULL,
  Action TEXT NOT NULL,
  OccurredAt TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR REPLACE INTO WebMeta(Key,Value,UpdatedAt)
VALUES('backend_schema','1',datetime('now'));
