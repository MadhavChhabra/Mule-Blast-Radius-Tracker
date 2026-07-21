-- Which of the consumer's own inbound endpoints makes this call (e.g. "GET /orders/{id}"). Lets the
-- tool answer "for this one endpoint, what does it call?" — the per-endpoint / property-file view.
-- Null for hand-written or app-level (whole-API) dependencies.
alter table dependency_edge add column consumer_endpoint varchar(512);
