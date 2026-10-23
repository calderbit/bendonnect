#!/bin/sh
# Runs the proof gate and every pure test; exits nonzero on any failure.
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.bend/bin:$PATH"
# Native builds need clang 14+; fall back to zig's bundled clang when it is absent.
if ! command -v clang >/dev/null 2>&1 && command -v zig >/dev/null 2>&1; then
  shim=$(mktemp -d)
  trap 'rm -rf "$shim"' EXIT
  printf '#!/bin/sh\nif [ "$1" = "--version" ]; then echo "clang version 20.1.0"; exit 0; fi\nexec zig cc "$@"\n' > "$shim/clang"
  chmod +x "$shim/clang"
  export PATH="$shim:$PATH"
fi
fail=0
out=$(bend PROOF.bend 2>&1)
case $out in *"ALL PROOFS CHECK"*) echo "PASS proofs";; *) echo "FAIL proofs"; echo "$out" | head -20; fail=1;; esac
for t in tests/*_test.bend; do
  out=$(bend "$t" 2>&1)
  bad=$(printf '%s' "$out" | grep -cE 'False\{\}|"FAIL|Error' || true)
  if [ "$bad" -eq 0 ]; then echo "PASS $t"; else echo "FAIL $t"; printf '%s\n' "$out" | head -c 2000; fail=1; fi
done
exit $fail
