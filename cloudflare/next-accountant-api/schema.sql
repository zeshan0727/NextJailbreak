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

INSERT OR REPLACE INTO WebMeta(Key,Value,UpdatedAt)
VALUES('backend_schema','1',datetime('now'));
