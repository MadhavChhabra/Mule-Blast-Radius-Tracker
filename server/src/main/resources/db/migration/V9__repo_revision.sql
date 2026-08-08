-- Last commit successfully scanned per repo, so a re-sync can skip repos that have not moved.
-- Keyed by the normalized (credential-free, lowercase) URL so an org URL and a directly
-- registered repo resolve to the same row.
create table repo_revision (
    url_key    varchar(1024) not null primary key,
    commit_sha varchar(64) not null,
    scanned_at timestamp not null default current_timestamp
);
