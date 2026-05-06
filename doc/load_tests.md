# Load Tests

Load smoke tests live in `e2e/load_test.rb` and run through invoke tasks.

The runner creates a realistic group-stage tournament over HTTP, then measures:

- concurrent `GET /tournaments/:id` reads at each configured client level
- active ActionCable subscriptions to `TournamentChannel`, opened in bounded
  batches so the test measures 200 active sockets instead of only handshake
  burst capacity
- `/metrics` websocket gauges and process counters after the run

It prints relative timings such as p50, p95, max, and requests per second. The
CI goal is not a fixed benchmark. The job fails when requests error, websocket
clients cannot subscribe, or ActionCable connection metrics do not reflect the
opened clients.

Useful commands:

- `inv verify-load-test`
- `inv load-test --base-url=http://127.0.0.1:3000`
- `inv load-test --http-clients=1,10,50,100 --websocket-clients=1,10,50,100,200`
- `inv blackbox-load-service`

Useful environment overrides:

- `TURNIERE_LOAD_HTTP_CLIENTS=1,10,50,100`
- `TURNIERE_LOAD_WEBSOCKET_CLIENTS=1,10,50,100,200`
- `TURNIERE_LOAD_HTTP_REQUESTS_PER_CLIENT=3`
- `TURNIERE_LOAD_WEBSOCKET_HOLD_SECONDS=1.0`
- `TURNIERE_LOAD_WEBSOCKET_CONNECT_BATCH_SIZE=25`
- `TURNIERE_LOAD_GROUP_COUNT=4`
- `TURNIERE_LOAD_TEAMS_PER_GROUP=4`
- `TURNIERE_LOAD_PLAYOFF_TEAMS=8`
- `TURNIERE_LOAD_FORMAT=json`

GitLab CI runs `rails load smoke` against the production image with Postgres,
covering read pressure up to 100 HTTP clients and active websocket pressure up
to 200 clients.
