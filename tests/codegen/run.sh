#!/usr/bin/env bash
# protoc-gen-bend test suite. Generates code from tests/codegen/proto/kitchen.proto, then:
#   1. every generated Bend module must print ALL PROOFS CHECK;
#   2. Go writes golden vectors (binary hex + canonical protojson) from protoc-gen-go output;
#   3. kitchen_test.bend decodes them, re-encodes (byte-identical to Go) and decodes the JSON;
#   4. Go parses what Bend encoded (binary and JSON) back and compares with proto.Equal;
#   5. edge cases (empty message, keyword names, cross-file imports, recursion through a oneof,
#      services of all four kinds) compile; proto2 and mutually recursive protos are rejected;
#   6. generation is deterministic;
#   7. the greet example end to end against connect-go (SKIP_E2E=1 skips it).
# Exits nonzero on any failure.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/tools.sh"
fail=0
pass() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
proofs() { # proofs <file>
  out=$(bend "$1" 2>&1 | head -c 4000)
  case $out in *"ALL PROOFS CHECK"*) pass "proofs $1";; *) bad "proofs $1"; echo "$out" | head -20;; esac
}

build_bend_plugin
build_go_plugins
cd "$HERE" || exit 2

# 1. generate
$BUF generate || { echo "buf generate failed"; exit 2; }
go run ./golden gen vectors || { echo "golden gen failed"; exit 2; }
proofs "$ROOT/tests/codegen/gen/bend/kitchen_pb.bend"

# 2-4. kitchen-sink vectors
bend kitchen_test.bend >"$HERE/bin/kitchen_test.out" 2>&1
grep -E '^(PASS|FAIL)' "$HERE/bin/kitchen_test.out"
if grep -q '^FAIL' "$HERE/bin/kitchen_test.out" || ! grep -q '^PASS' "$HERE/bin/kitchen_test.out"; then
  bad "kitchen_test.bend"; head -c 3000 "$HERE/bin/kitchen_test.out" | grep -v '^\(bin\|json\) '
else pass "kitchen_test.bend"; fi
if go run ./golden check vectors "$HERE/bin/kitchen_test.out" >"$HERE/bin/go_check.out" 2>&1; then
  pass "go parses bend output ($(grep -c '^PASS' "$HERE/bin/go_check.out") checks)"
else bad "go parses bend output"; grep -v '^PASS' "$HERE/bin/go_check.out" | head -20; fi

# 5. edge cases
(cd edge/ok && rm -rf gen && $BUF generate) || bad "edge generate"
for f in edge/ok/gen/app/app_pb.bend edge/ok/gen/shared/common_pb.bend; do proofs "$HERE/$f"; done
[ -f edge/ok/gen/app/app_connect.bend ] && pass "edge services generated" || bad "edge services generated"
# service stubs of all four kinds: stubs_test.bend instantiates the handler templates and client
# functions; the transport is unsafe, so compile to C (no proofs) and look for real errors.
out=$(bend edge/ok/stubs_test.bend -o "$HERE/bin/edge_stubs.c" 2>&1 | head -c 3000)
if [ -z "$out" ]; then pass "edge connect stubs typecheck"; else bad "edge connect stubs typecheck"; echo "$out"; fi
expect_reject() { # expect_reject <proto> <substring>
  rm -rf edge/bad/gen
  out=$(cd edge/bad && $BUF generate --path "$1" 2>&1)
  case $out in *"$2"*) pass "rejects $1";; *) bad "rejects $1 (wanted '$2')"; echo "$out" | head -5;; esac
}
expect_reject proto2.proto "only proto3"
expect_reject mutual.proto "mutually recursive"

# 6. determinism
rm -rf "$HERE/bin/regen" && mkdir -p "$HERE/bin/regen"
cat >"$HERE/bin/regen.yaml" <<YAML
version: v2
plugins:
  - local: ../../cmd/protoc-gen-bend/bin/protoc-gen-bend
    out: bin/regen
    opt:
      - runtime=../../../..
YAML
$BUF generate --template "$HERE/bin/regen.yaml" 2>/dev/null
if diff -q "$HERE/bin/regen/kitchen_pb.bend" "$HERE/gen/bend/kitchen_pb.bend" >/dev/null; then pass "deterministic output"; else bad "deterministic output"; fi

# 7. greet example
proofs "$ROOT/examples/greet/greet_pb.bend"
if [ "${SKIP_E2E:-0}" != 1 ]; then
  if SKIP_GEN=0 "$ROOT/examples/greet/run_e2e.sh" >"$HERE/bin/e2e.out" 2>&1; then pass "greet e2e ($(grep -c '^PASS' "$HERE/bin/e2e.out") checks)"; else bad "greet e2e"; tail -15 "$HERE/bin/e2e.out"; fi
fi
exit "$fail"
