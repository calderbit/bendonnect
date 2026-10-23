# Working on Bendonette (notes for agents)

Bendonette is a ConnectRPC (https://connectrpc.com/docs/protocol/) library for Bend 2.

## Setup
- `export PATH="$HOME/.bend/bin:$PATH"` (Bend 2.0.38). Read `~/.bend/guide/GUIDE.md` fully before writing Bend.
- Native builds (`bend f.bend -o f`) need clang; use the zig shim:
  `export PATH=/tmp/claude-1000/-home-calderbit-dev-Bendonette/af17a737-1765-4d6a-97d6-1c3fc107a611/scratchpad/bin:$PATH`.
- `bend base [Name]` prints Base. Fetched hub packages are cached in `~/.bend/lib/<hash>/` (read their source there).

## Dependencies (pinned)
```
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes        # Bytes{len, buf: Array<U32>} affine, 4 bytes/word
import bend-kit-encoding@0.4.0.0/encoding.bend as Enc    # Enc.utf8.encode / Enc.utf8.decode
import bend-kit-json@0.6.1.1/json.bend as Json           # Json.Val, parse.bytes, encode.bytes
import bend-kit-url@0.4.1.0/url.bend as Url              # pct.decode
import bend-kit-http@0.36.0.0/http.bend as Http          # TRANSPORT ONLY (uses @unsafe/foreign code)
```

## Layout and rules
- `src/*.bend` pure core: MUST NOT import bend-kit-http, use `@unsafe`, or foreign effects.
  `bend src/<file>.bend` must print ALL PROOFS CHECK.
- `src/transport/*.bend` server and client IO on bend-kit-http (may be unsafe).
- `tests/*_test.bend`: runnable tests; `main` returns a List of results or IO that prints PASS/FAIL lines.
- `LAWS.bend` and `PROOF.bend` at the root are owned by the lead. Put proposed laws in (create the dir)
  `proofs/<area>_laws.bend` and their proofs in `proofs/<area>_proof.bend` (same convention:
  `law x` proven by `def Laws.x` in the proof file, which imports the laws file `as Laws`).
- Idioms learned so far:
  - No mutual recursion; for early exit pass the recursive call as a thunk to a non-recursive
    helper: `helper(cond, x, u => go(rest, s))` (see `src/code.bend`).
  - `match` only on params/pattern vars; operators need a type: `((n >> 8n) .&. 255 : U32)`.
  - Pairs `A & B` are Type-kinded; for a reusable list of pairs declare a small `is Data` type.
  - Concrete facts prove by case analysis + `{==}` (see PROOF.bend).
