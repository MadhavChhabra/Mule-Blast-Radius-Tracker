-- Per-source outcome of the last sync, so the Sources list can show which repos actually
-- contributed apps and which one silently failed, instead of only the run that just finished.
alter table scan_source add column last_synced_at timestamp;
alter table scan_source add column last_apps int;
alter table scan_source add column last_error varchar(1024);
