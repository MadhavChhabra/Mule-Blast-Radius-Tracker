-- Private repos are registered as https://<token>@host/org, which put the token in scan_source.url —
-- plaintext in the database, and echoed back by /api/sources, /api/audit and the dashboard.
-- The credential now lives in its own encrypted column and url keeps only the clean address.
-- Rows written before this are split and encrypted on the next startup (SourcesService.migrateStoredCredentials).
alter table scan_source add column credential varchar(2048);
