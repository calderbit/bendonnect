#!/bin/sh
# Runs the proof gate and every pure test; exits nonzero on any failure.
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.bend/bin:$PATH"
fail=0
out=$(bend PROOF.bend 2>&1)
case $out in *"ALL PROOFS CHECK"*) echo "PASS proofs";; *) echo "FAIL proofs"; echo "$out" | head -20; fail=1;; esac
for t in tests/*_test.bend; do
  out=$(bend "$t" 2>&1)
  bad=$(printf '%s' "$out" | grep -cE 'False\{\}|"FAIL|Error' || true)
  if [ "$bad" -eq 0 ]; then echo "PASS $t"; else echo "FAIL $t"; printf '%s\n' "$out" | head -c 2000; fail=1; fi
done
exit $fail
