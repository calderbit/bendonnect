#!/usr/bin/env bash
# End to end: regenerates the Bend and Go code from greet.proto, starts the Bend GreetService
# (server.bend, port 8787), runs the connect-go client in goclient/ against it with the proto and
# json codecs, kills ONLY the server PID it started, and exits with the client's status.
# Env: PORT (default 8787; must match server.bend), WAIT_SECS (default 240), SERVER_BIN (a native
# build of server.bend; skips the runner), SKIP_GEN=1 (do not regenerate).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../../tests/codegen/tools.sh"
PORT="${PORT:-8787}"
LOG="${TMPDIR:-/tmp}/greet_e2e_server.$$.log"

if [ "${SKIP_GEN:-0}" != 1 ]; then
  build_bend_plugin
  build_go_plugins
  (cd "$HERE" && $BUF generate) || exit 2
fi

cd "$ROOT" || exit 2
if [ -n "${SERVER_BIN:-}" ]; then
  "$SERVER_BIN" >"$LOG" 2>&1 &
else
  bend examples/greet/server.bend >"$LOG" 2>&1 &
fi
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; }
trap cleanup EXIT

ready=0
for _ in $(seq 1 "${WAIT_SECS:-240}"); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then echo "server exited early; log:"; cat "$LOG"; exit 2; fi
  if ss -ltn 2>/dev/null | grep -q "127.0.0.1:$PORT "; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || { echo "server did not open port $PORT; log:"; cat "$LOG"; exit 2; }

(cd "$HERE/goclient" && go run . -url "http://127.0.0.1:$PORT")
STATUS=$?
[ "$STATUS" = 0 ] || exit "$STATUS"

# The Bend client (generated client functions) against the same server.
cd "$ROOT" && bend examples/greet/client.bend >"$LOG.client" 2>&1
got=$(grep '^  Hello' "$LOG.client" | sed 's/^  //' | tr '\n' '|' | sed 's/|$//')
want_all='Hello, Ada!|Hello, Grace (1)!|Hello, Grace (2)!|Hello, Grace (3)!|Hello, Ada, Grace!|Hello, Edsger!'
if [ "$got" = "$want_all" ]; then echo "PASS bend-client (greet, greet_many, greet_all, greet_get)"; STATUS=0
else echo "FAIL bend-client: got '$got'"; cat "$LOG.client"; STATUS=1; fi
rm -f "$LOG.client"
exit "$STATUS"
