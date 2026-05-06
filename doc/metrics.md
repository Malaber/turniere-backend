# Metrics

The backend exposes Prometheus text metrics at `GET /metrics`.

The endpoint is unauthenticated so monitoring systems can scrape it directly. It
reports per-process in-memory values:

- `turniere_http_requests_total`
- `turniere_http_request_duration_seconds`
- `turniere_action_cable_connections`
- `turniere_action_cable_connections_total`
- `turniere_process_uptime_seconds`
- `turniere_ruby_threads`
- `turniere_active_record_connection_pool`
- `turniere_build_info`

This covers app-level request and websocket health. Logs, traces, host metrics,
and multi-process aggregation should remain infrastructure concerns. If Puma is
ever run with multiple worker processes, scrape each process or container replica
and aggregate in the monitoring backend.
