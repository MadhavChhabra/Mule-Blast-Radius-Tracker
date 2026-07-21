-- A human-readable label for an API node, distinct from its canonical id (the Exchange assetId /
-- Maven artifactId used to join repo-scan and Anypoint discovery onto one node).
alter table api add column display_name varchar(255);
