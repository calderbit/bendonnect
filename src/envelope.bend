# Connect streaming envelope: 1 flags byte + 4-byte big-endian length + message.
# https://connectrpc.com/docs/protocol/#streaming-request
#
# Design notes:
# - Reserved flag bits (anything besides 1 = compressed, 2 = end-stream) are KEPT in
#   `flags` by decode (never rejected); the caller decides what to do with them.
#   encode writes the low 8 bits of `flags`.
# - decode reports Bad as soon as a header announces a message larger than `max`,
#   before the body has arrived.
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

type Envelope is Type:
  Envelope{flags: U32, data: Bytes.Bytes}

def flag_compressed() -> U32:
  1

def flag_end() -> U32:
  2

# 5-byte header followed by the message.
def encode.of(+flags: U32, r: Bytes.Bytes & U32) -> Bytes.Bytes:
  (data, len) = r
  h1 = Bytes.set(Bytes.new(5), 0, (flags .&. 255 : U32))
  h2 = Bytes.set.u32be(h1, 1, len)
  Bytes.append(h2, data)

def encode(e: Envelope) -> Bytes.Bytes:
  Envelope{+flags, data} = e
  encode.of(flags, Bytes.length(data))

# Encodes every envelope in parallel, then concatenates.
def encode_list(es: List<&1, Envelope>) -> List<&1, Bytes.Bytes>:
  match es:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      a b = encode(h) encode_list(t)
      a <> b

def encode_all(es: List<&1, Envelope>) -> Bytes.Bytes:
  Bytes.concat(encode_list(es))

type Step is Type:
  Need{buf: Bytes.Bytes}
  Got{env: Envelope, rest: Bytes.Bytes}
  Bad{reason: String}

def decode.too_big(len: U32, max: U32) -> String:
  "message size " ++ U32.show(len) ++ " is larger than configured max " ++ U32.show(max)

def decode.rest(r: Bytes.Bytes & Bytes.Bytes, +flags: U32, data: Bytes.Bytes) -> Step:
  (b, rest) = r
  Got{Envelope{flags, data}, rest}

def decode.body(r: Bytes.Bytes & Bytes.Bytes, +flags: U32, +len: U32, +n: U32) -> Step:
  (b, data) = r
  decode.rest(Bytes.slice(b, (5 + len : U32), (n - 5 - len : U32)), flags, data)

def decode.cut(buf: Bytes.Bytes, +flags: U32, +len: U32, +n: U32) -> Step:
  decode.body(Bytes.slice(buf, 5, len), flags, len, n)

def decode.fit(short: Bool, buf: Bytes.Bytes, +flags: U32, +len: U32, +n: U32) -> Step:
  match short:
    case True{}:
      Need{buf}
    case False{}:
      decode.cut(buf, flags, len, n)

def decode.size(big: Bool, buf: Bytes.Bytes, +flags: U32, +len: U32, +n: U32, +max: U32) -> Step:
  match big:
    case True{}:
      Bad{decode.too_big(len, max)}
    case False{}:
      decode.fit(U32.is_lt((n - 5 : U32), len), buf, flags, len, n)

def decode.len(r: Bytes.Bytes & Maybe<&2, U32>, +flags: U32, +n: U32, +max: U32) -> Step:
  (buf, m) = r
  match m:
    case None{}:
      Bad{"truncated envelope header"}
    case Some{+len}:
      decode.size(U32.is_gt(len, max), buf, flags, len, n, max)

def decode.flags(r: Bytes.Bytes & Maybe<&2, U32>, +n: U32, +max: U32) -> Step:
  (buf, m) = r
  match m:
    case None{}:
      Bad{"truncated envelope header"}
    case Some{+flags}:
      decode.len(Bytes.get.u32be(buf, 1), flags, n, max)

def decode.hdr(short: Bool, buf: Bytes.Bytes, +n: U32, +max: U32) -> Step:
  match short:
    case True{}:
      Need{buf}
    case False{}:
      decode.flags(Bytes.get(buf, 0), n, max)

# Reads one envelope off the front of buf: Need when more bytes are required, Got with
# the remaining bytes, Bad when the announced size exceeds max.
def decode.start(r: Bytes.Bytes & U32, +max: U32) -> Step:
  (b, +n) = r
  decode.hdr(U32.is_lt(n, 5), b, n, max)

def decode(buf: Bytes.Bytes, +max: U32) -> Step:
  decode.start(Bytes.length(buf), max)

def decode_all.cons(env: Envelope, r: Result<&2, &1, String, List<&1, Envelope>>) -> Result<&2, &1, String, List<&1, Envelope>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{l}:
      Done{env <> l}

def decode_all.end(empty: Bool) -> Result<&2, &1, String, List<&1, Envelope>>:
  match empty:
    case True{}:
      Done{Nil{}}
    case False{}:
      Fail{"incomplete envelope at end of body"}

def decode_all.fin(r: Bytes.Bytes & U32) -> Result<&2, &1, String, List<&1, Envelope>>:
  (b, +n) = r
  decode_all.end(U32.is_eq(n, 0))

# fuel: every envelope takes at least 5 bytes, so (bytes + 1) steps always suffice.
def decode_all.go(fuel: Nat, s: Step, +max: U32) -> Result<&2, &1, String, List<&1, Envelope>>:
  match fuel:
    case 0n:
      Fail{"envelope decoder out of fuel"}
    case 1n+p:
      match s:
        case Need{b}:
          decode_all.fin(Bytes.length(b))
        case Bad{r}:
          Fail{r}
        case Got{env, rest}:
          decode_all.cons(env, decode_all.go(p, decode(rest, max), max))

def decode_all.start(r: Bytes.Bytes & U32, +max: U32) -> Result<&2, &1, String, List<&1, Envelope>>:
  (b, +n) = r
  decode_all.go(1n+U32.to_nat(n), decode(b, max), max)

# Every envelope of a complete body; a trailing partial envelope is a Fail.
def decode_all(buf: Bytes.Bytes, +max: U32) -> Result<&2, &1, String, List<&1, Envelope>>:
  decode_all.start(Bytes.length(buf), max)
