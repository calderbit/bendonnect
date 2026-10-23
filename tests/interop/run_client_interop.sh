#!/usr/bin/env bash
# Runs the Bend client (examples/test_client.bend) against the Go reference server.
# Starts only the server it builds, kills only that PID, exits with the client's status.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.bend/bin:$PATH"
ADDR="${ADDR:-127.0.0.1:8788}"
HOST="${ADDR%:*}"; PORT="${ADDR##*:}"
TMP="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

(cd "$ROOT/tests/interop" && go build -o "$TMP/server" ./server) || { echo "go build failed"; exit 2; }
"$TMP/server" -addr "$ADDR" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 50); do
  if (exec 3<>"/dev/tcp/$HOST/$PORT") 2>/dev/null; then break; fi
  kill -0 "$SERVER_PID" 2>/dev/null || { echo "server died:"; cat "$TMP/server.log"; exit 2; }
  sleep 0.1
done

cd "$ROOT"
bend examples/test_client.bend "http://$ADDR"
exit $?
