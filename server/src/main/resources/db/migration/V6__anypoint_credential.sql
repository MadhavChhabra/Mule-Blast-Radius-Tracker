-- Persisted Anypoint Connected App credential so the user connects once and does not re-enter it on
-- every restart. Single row (id = 1). The client secret is stored ENCRYPTED (AES-GCM via
-- CredentialCipher); it is only persisted when an encryption key is available (auto-managed key file
-- on desktop, or APIGUARD_ENCRYPTION_KEY on a server). Disable with apiguard.anypoint.persist=false.
create table anypoint_credential (
    id            int primary key,
    client_id     varchar(512),
    client_secret varchar(4096),
    org_id        varchar(256),
    environment   varchar(256),
    updated_at    timestamp not null default current_timestamp
);
