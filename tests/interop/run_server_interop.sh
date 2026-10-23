#!/usr/bin/env bash
# Starts the Bendonette test server (examples/test_server.bend, port 8787), waits for the port,
# runs the Go interop client against it, kills ONLY the server PID it started, exits with the
# client's status.  Env: BEND_BIN (default `bend`), SERVER_BIN (a native build; skips the runner),
# PORT (default 8787; must match the server), WAIT_SECS (default 180).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PORT="${PORT:-8787}"
export PATH="$HOME/.bend/bin:$PATH"
LOG="${TMPDIR:-/tmp}/bend_interop_server.$$.log"

cd "$ROOT" || exit 2
if [ -n "${SERVER_BIN:-}" ]; then
  "$SERVER_BIN" >"$LOG" 2>&1 &
else
  "${BEND_BIN:-bend}" examples/test_server.bend >"$LOG" 2>&1 &
fi
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; }
trap cleanup EXIT

ready=0
for _ in $(seq 1 "${WAIT_SECS:-180}"); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then echo "server exited early; log:"; cat "$LOG"; exit 2; fi
  if ss -ltn 2>/dev/null | grep -q "127.0.0.1:$PORT "; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || { echo "server did not open port $PORT; log:"; cat "$LOG"; exit 2; }

cd "$HERE" && go run ./client -url "http://127.0.0.1:$PORT" "$@"
STATUS=$?
exit "$STATUS"
