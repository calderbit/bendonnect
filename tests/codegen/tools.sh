# Sourced by tests/codegen/run.sh and examples/greet/run_e2e.sh.
# Sets ROOT, TOOLS and BUF; builds protoc-gen-bend / protoc-gen-go / protoc-gen-connect-go into $TOOLS.
ROOT=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)
[ -f "$ROOT/AGENTS.md" ] || ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TOOLS="$ROOT/tests/codegen/bin"
mkdir -p "$TOOLS"
export PATH="$HOME/.bend/bin:$TOOLS:$PATH"
# Native builds need clang 14+; fall back to zig's bundled clang when it is absent.
if ! command -v clang >/dev/null 2>&1 && command -v zig >/dev/null 2>&1; then
  printf '#!/bin/sh\nif [ "$1" = "--version" ]; then echo "clang version 20.1.0"; exit 0; fi\nexec zig cc "$@"\n' > "$TOOLS/clang"
  chmod +x "$TOOLS/clang"
fi
export GOFLAGS=-mod=mod

# buf: PATH first (mise shims can be unconfigured), then mise exec, then go run.
if buf --version >/dev/null 2>&1; then BUF="buf"
elif mise exec buf@1.73.0 -- buf --version >/dev/null 2>&1; then BUF="mise exec buf@1.73.0 -- buf"
else echo "buf not found" >&2; exit 2; fi

build_bend_plugin() {
  mkdir -p "$ROOT/cmd/protoc-gen-bend/bin"
  (cd "$ROOT/cmd/protoc-gen-bend" && go build -o bin/protoc-gen-bend .) || exit 2
}
build_go_plugins() {
  (cd "$ROOT/tests/codegen" && go build -o "$TOOLS/protoc-gen-go" google.golang.org/protobuf/cmd/protoc-gen-go) || exit 2
  (cd "$ROOT/examples/greet/goclient" && go build -o "$TOOLS/protoc-gen-connect-go" connectrpc.com/connect/cmd/protoc-gen-connect-go) || exit 2
}
