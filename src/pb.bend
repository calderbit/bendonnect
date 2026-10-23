# Protobuf binary runtime for generated code (alias Pbr). Pure. Reference: docs/runtime.md.
#
# Built on bend-kit-protobuf (Pb): Word64, Value, Field, decode/encode, packed_decode/encode.
# Readers answer Result<&2, &1, String, T> (wrong wire type or malformed input -> Fail).
# Writers answer List<&1, Pb.Field> so a message is encoded by concatenating per-field lists.
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-encoding@0.4.0.0/encoding.bend as Enc
import bend-kit-protobuf@0.1.0.0/protobuf.bend as Pb

# ------------------------------------------------------------------ limits

def max_size() -> U32:
  2147483647

def max_depth() -> Nat:
  100n

# ------------------------------------------------------------------ small list helpers

def rev(-A: Data, xs: List<&2, A>) -> List<&2, A>:
  List.reverse(&2, A, xs)

def cat(xs: List<&1, Pb.Field>, ys: List<&1, Pb.Field>) -> List<&1, Pb.Field>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      h <> cat(t, ys)

def cat.all(parts: List<&1, List<&1, Pb.Field>>) -> List<&1, Pb.Field>:
  match parts:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      cat(h, cat.all(t))

def pick.then(z: Bool, acc: String, next: Unit -> String) -> String:
  match z:
    case True{}:
      acc
    case False{}:
      next(Unit{})

# ------------------------------------------------------------------ Word64

def word64.of_u32(+x: U32) -> Pb.Word64:
  Pb.Word64{0, x}

# Sign-extends a 32-bit two's complement value.
def word64.of_i32(+x: U32) -> Pb.Word64:
  Pb.Word64{(0 - (x >> 31n) : U32), x}

def word64.hi(w: Pb.Word64) -> U32:
  Pb.Word64{h, l} = w
  h

def word64.lo(w: Pb.Word64) -> U32:
  Pb.Word64{h, l} = w
  l

def word64.is_zero(w: Pb.Word64) -> Bool:
  Pb.Word64.is_zero(w)

def word64.eq(a: Pb.Word64, b: Pb.Word64) -> Bool:
  Pb.Word64{ah, al} = a
  Pb.Word64{bh, bl} = b
  U32.is_eq(ah, bh) && U32.is_eq(al, bl)

# True when the sign bit (bit 63) is set.
def word64.is_neg(w: Pb.Word64) -> Bool:
  Pb.Word64{h, l} = w
  U32.is_ne((h >> 31n : U32), 0)

# Two's complement negation.
def word64.neg(w: Pb.Word64) -> Pb.Word64:
  Pb.Word64{+h, +l} = w
  Pb.Word64{(0 - h - Bool.to_u32(Bool.not(U32.is_zero(l))) : U32), (0 - l : U32)}

# Logical shifts, n in 0..63.
def word64.shl(w: Pb.Word64, +n: U32) -> Pb.Word64:
  Pb.Word64{+h, +l} = w
  +a = (n .&. 31 : U32)
  +big = U32.is_ge(n, 32)
  Pb.Word64{
    Bool.pick(U32, big, (l << U32.to_nat(a) : U32), ((h << U32.to_nat(a)) .|. (l >> U32.to_nat((32 - a : U32))) : U32)),
    Bool.pick(U32, big, 0, (l << U32.to_nat(a) : U32))}

def word64.shr(w: Pb.Word64, +n: U32) -> Pb.Word64:
  Pb.Word64{+h, +l} = w
  +a = (n .&. 31 : U32)
  +big = U32.is_ge(n, 32)
  Pb.Word64{
    Bool.pick(U32, big, 0, (h >> U32.to_nat(a) : U32)),
    Bool.pick(U32, big, (h >> U32.to_nat(a) : U32), ((l >> U32.to_nat(a)) .|. (h << U32.to_nat((32 - a : U32))) : U32))}

# Decimal conversion works on 16-bit limbs so every intermediate fits in U32.
type Dm is Data:
  Dm{q: Pb.Word64, r: U32}

type Qr is Data:
  Qr{q: U32, r: U32}

def dm.step(+rem: U32, +chunk: U32) -> Qr:
  +cur = (rem * 65536 + chunk : U32)
  Qr{(cur / 10 : U32), (cur % 10 : U32)}

def dm.d(+q3: U32, +q2: U32, +q1: U32, s: Qr) -> Dm:
  Qr{q0, r0} = s
  Dm{Pb.Word64{((q3 << 16n) .|. q2 : U32), ((q1 << 16n) .|. q0 : U32)}, r0}

def dm.c(+ll: U32, +q3: U32, +q2: U32, s: Qr) -> Dm:
  Qr{q1, r1} = s
  dm.d(q3, q2, q1, dm.step(r1, ll))

def dm.b(+l: U32, +q3: U32, s: Qr) -> Dm:
  Qr{q2, r2} = s
  dm.c((l .&. 65535 : U32), q3, q2, dm.step(r2, (l >> 16n : U32)))

def dm.a(+hl: U32, +l: U32, s: Qr) -> Dm:
  Qr{q3, r3} = s
  dm.b(l, q3, dm.step(r3, hl))

def dm.q(d: Dm) -> Pb.Word64:
  Dm{q, r} = d
  q

def dm.r(d: Dm) -> U32:
  Dm{q, r} = d
  r

def word64.divmod10(w: Pb.Word64) -> Dm:
  Pb.Word64{+h, +l} = w
  dm.a((h .&. 65535 : U32), l, dm.step(0, (h >> 16n : U32)))

def show_u.go(fuel: Nat, +w: Pb.Word64, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      +d = word64.divmod10(w)
      pick.then(Pb.Word64.is_zero(w), acc, u => show_u.go(p, dm.q(d), SCon{Chr{(48 + dm.r(d) : U32)}, acc}))

# Unsigned decimal text.
def word64.show_u(+w: Pb.Word64) -> String:
  Bool.pick(String, Pb.Word64.is_zero(w), "0", show_u.go(20n, w, ""))

def show_s.go(neg: Bool, +w: Pb.Word64) -> String:
  match neg:
    case True{}:
      String.append("-", word64.show_u(word64.neg(w)))
    case False{}:
      word64.show_u(w)

# Signed (two's complement) decimal text.
def word64.show_s(+w: Pb.Word64) -> String:
  show_s.go(word64.is_neg(w), w)

type Acc is Data:
  Acc{w: Pb.Word64, ovf: Bool}

type Kc is Data:
  Kc{c: U32, k: U32}

def ma.step(+chunk: U32, +carry: U32) -> Kc:
  +x = (chunk * 10 + carry : U32)
  Kc{(x .&. 65535 : U32), (x >> 16n : U32)}

def ma.d(+c0: U32, +c1: U32, +c2: U32, s: Kc) -> Acc:
  Kc{c3, k3} = s
  Acc{Pb.Word64{((c3 << 16n) .|. c2 : U32), ((c1 << 16n) .|. c0 : U32)}, U32.is_ne(k3, 0)}

def ma.c(+h: U32, +c0: U32, +c1: U32, s: Kc) -> Acc:
  Kc{c2, k2} = s
  ma.d(c0, c1, c2, ma.step((h >> 16n : U32), k2))

def ma.b(+h: U32, +l: U32, +c0: U32, s: Kc) -> Acc:
  Kc{c1, k1} = s
  ma.c(h, c0, c1, ma.step((h .&. 65535 : U32), k1))

def ma.a(+h: U32, +l: U32, s: Kc) -> Acc:
  Kc{c0, k0} = s
  ma.b(h, l, c0, ma.step((l >> 16n : U32), k0))

# w * 10 + d (d < 10), with an overflow flag.
def word64.muladd10(w: Pb.Word64, d: U32) -> Acc:
  Pb.Word64{+h, +l} = w
  ma.a(h, l, ma.step((l .&. 65535 : U32), d))

def acc.w(a: Acc) -> Pb.Word64:
  Acc{w, o} = a
  w

def acc.o(a: Acc) -> Bool:
  Acc{w, o} = a
  o

def read_u.go(s: String, w: Pb.Word64, bad: Bool) -> Maybe<&2, Pb.Word64>:
  match s:
    case SNil{}:
      Bool.pick(Maybe<&2, Pb.Word64>, bad, None{}, Some{w})
    case SCon{Chr{+c}, t}:
      +digit = U32.is_ge(c, 48) && U32.is_le(c, 57)
      +a = word64.muladd10(w, Bool.pick(U32, digit, (c - 48 : U32), 0))
      read_u.go(t, acc.w(a), bad || acc.o(a) || Bool.not(digit))

# Decimal digits -> Word64; None on empty input, a non-digit, or overflow past 2^64-1.
def word64.read_u(+s: String) -> Maybe<&2, Pb.Word64>:
  Bool.pick(Maybe<&2, Pb.Word64>, String.is_empty(s), None{}, read_u.go(s, Pb.Word64{0, 0}, False{}))

def read_s.neg(m: Maybe<&2, Pb.Word64>) -> Maybe<&2, Pb.Word64>:
  match m:
    case None{}:
      None{}
    case Some{w}:
      Pb.Word64{+h, +l} = w
      Bool.pick(Maybe<&2, Pb.Word64>,
        U32.is_lt(h, 2147483648) || (U32.is_eq(h, 2147483648) && U32.is_zero(l)),
        Some{word64.neg(Pb.Word64{h, l})}, None{})

def read_s.pos(m: Maybe<&2, Pb.Word64>) -> Maybe<&2, Pb.Word64>:
  match m:
    case None{}:
      None{}
    case Some{w}:
      Pb.Word64{+h, +l} = w
      Bool.pick(Maybe<&2, Pb.Word64>, U32.is_lt(h, 2147483648), Some{Pb.Word64{h, l}}, None{})

def read_s.go(neg: Bool, +c: U32, +t: String) -> Maybe<&2, Pb.Word64>:
  match neg:
    case True{}:
      read_s.neg(word64.read_u(t))
    case False{}:
      read_s.pos(word64.read_u(SCon{Chr{c}, t}))

# Optional '-' then decimal digits -> two's complement Word64; None when it does not fit in int64.
def word64.read_s(+s: String) -> Maybe<&2, Pb.Word64>:
  match s:
    case SNil{}:
      None{}
    case SCon{Chr{+c}, +t}:
      read_s.go(U32.is_eq(c, 45), c, t)

# ------------------------------------------------------------------ bytes, strings, zigzag

def codes.to_chars(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      SNil{}
    case Con{h, t}:
      SCon{Chr{h}, codes.to_chars(t)}

def chars.to_codes(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      c <> chars.to_codes(t)

# One byte per cell (only the low 8 bits of each cell are kept).
def bytes.of_list(xs: List<&2, U32>) -> Bytes.Bytes:
  Bytes.from_string(codes.to_chars(xs))

def bytes.to_list(b: Bytes.Bytes) -> List<&2, U32>:
  chars.to_codes(Bytes.to_string(b))

# UTF-8 (lone surrogates and out-of-range code points are replaced by U+FFFD).
def string.encode(+s: String) -> Bytes.Bytes:
  Enc.utf8.encode(s)

def lift2(-T: Data, what: String, r: Result<&2, &2, Pb.Error, T>) -> Result<&2, &1, String, T>:
  match r:
    case Fail{e}:
      Fail{what}
    case Done{x}:
      Done{x}

def lift1(-T: Type, what: String, r: Result<&2, &1, Pb.Error, T>) -> Result<&2, &1, String, T>:
  match r:
    case Fail{e}:
      Fail{what}
    case Done{x}:
      Done{x}

# Strict UTF-8 decoding.
def string.decode(b: Bytes.Bytes) -> Result<&2, &1, String, String>:
  lift2(String, "protobuf: invalid UTF-8 in string field", Pb.utf8.decode(b))

def zigzag32(+v: U32) -> U32:
  ((v << 1n) .^. (0 - (v >> 31n)) : U32)

def unzigzag32(+bits: U32) -> U32:
  Pb.unzigzag32(bits)

def zigzag64(w: Pb.Word64) -> Pb.Word64:
  Pb.Word64.zigzag(w)

def unzigzag64(w: Pb.Word64) -> Pb.Word64:
  Pb.Word64.unzigzag(w)

# ------------------------------------------------------------------ float / double

def f32.bits(+f: F32) -> U32:
  F32.bits(f)

def f32.of_bits(+u: U32) -> F32:
  Pb.float_of_bits(u)

# floor(log2 m) for m >= 1 (0 for m = 0).
def msb.go(fuel: Nat, +m: U32, +acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      msb.go(p, (m >> 1n : U32), (acc + Bool.to_u32(U32.is_gt(m, 1)) : U32))

def msb(+m: U32) -> U32:
  msb.go(24n, m, 0)

# IEEE binary32 bits -> binary64 bits (exact).
def double.of_f32bits(+b: U32) -> Pb.Word64:
  +s = ((b >> 31n) << 31n : U32)
  +e = ((b >> 23n) .&. 255 : U32)
  +m = (b .&. 8388607 : U32)
  +p = msb(m)
  +sub = word64.shl(Pb.Word64{0, (m - (1 << U32.to_nat(p)) : U32)}, (52 - p : U32))
  +mh = (m >> 3n : U32)
  +ml = ((m .&. 7) << 29n : U32)
  +nh = (s .|. ((e + 896) << 20n) .|. mh : U32)
  +sh = (s .|. 2146435072 .|. mh : U32)
  +uh = (s .|. ((p + 874) << 20n) .|. word64.hi(sub) : U32)
  Pb.Word64{
    Bool.pick(U32, U32.is_eq(e, 255), sh, Bool.pick(U32, U32.is_zero(e), Bool.pick(U32, U32.is_zero(m), s, uh), nh)),
    Bool.pick(U32, U32.is_zero(e), Bool.pick(U32, U32.is_zero(m), 0, word64.lo(sub)), ml)}

# IEEE binary64 bits -> binary32 bits, round to nearest even (overflow -> infinity, tiny -> zero).
def double.f32bits(w: Pb.Word64) -> U32:
  Pb.Word64{+h, +l} = w
  +s = ((h >> 31n) << 31n : U32)
  +e = ((h >> 20n) .&. 2047 : U32)
  +fh = (h .&. 1048575 : U32)
  +m23 = ((fh << 3n) .|. (l >> 29n) : U32)
  +rem = (l .&. 536870911 : U32)
  +up = U32.is_gt(rem, 268435456) || (U32.is_eq(rem, 268435456) && U32.is_eq((m23 .&. 1 : U32), 1))
  +normal = (((e - 896) << 23n) + m23 + Bool.to_u32(up) : U32)
  +special = Bool.pick(U32, U32.is_zero(fh) && U32.is_zero(l), 2139095040, (2143289344 .|. m23 : U32))
  +k = (926 - e : U32)
  +sig = {Pb.Word64{(fh .|. 1048576 : U32), l} : Pb.Word64}
  +mm = word64.lo(word64.shr(sig, k))
  +t = word64.shl(sig, (64 - k : U32))
  +th = word64.hi(t)
  +tl = word64.lo(t)
  +gt = U32.is_gt(th, 2147483648) || (U32.is_eq(th, 2147483648) && U32.is_ne(tl, 0))
  +eq = U32.is_eq(th, 2147483648) && U32.is_zero(tl)
  +up2 = gt || (eq && U32.is_eq((mm .&. 1 : U32), 1))
  +subn = (mm + Bool.to_u32(up2) : U32)
  (s .|. Bool.pick(U32, U32.is_eq(e, 2047), special,
        Bool.pick(U32, U32.is_ge(e, 1151), 2139095040,
        Bool.pick(U32, U32.is_ge(e, 897), normal,
        Bool.pick(U32, U32.is_ge(e, 873), subn, 0))))
    : U32)

# F32 <-> 64-bit wire bits. Doubles are LOSSY in this library: they are held in F32.
def double.bits(+f: F32) -> Pb.Word64:
  double.of_f32bits(F32.bits(f))

def double.of_bits(w: Pb.Word64) -> F32:
  Pb.float_of_bits(double.f32bits(w))

# ------------------------------------------------------------------ decode / encode

def decode(b: Bytes.Bytes) -> Result<&2, &1, String, List<&1, Pb.Field>>:
  lift1(List<&1, Pb.Field>, "protobuf: malformed message", Pb.decode(b, max_size(), max_depth()))

def encode.fin(r: Result<&2, &1, Pb.Error, Bytes.Bytes>) -> Bytes.Bytes:
  match r:
    case Fail{e}:
      Bytes.new(0)
    case Done{b}:
      b

# Never fails for well-formed field numbers (1..536870911); a bad field number yields empty bytes.
def encode(fs: List<&1, Pb.Field>) -> Bytes.Bytes:
  encode.fin(Pb.encode(fs, max_size(), max_depth()))

# ------------------------------------------------------------------ Value constructors

def value.double(+f: F32) -> Pb.Value:
  Pb.Fixed64{double.bits(f)}

def value.float(+f: F32) -> Pb.Value:
  Pb.from_float(f)

def value.int32(+x: U32) -> Pb.Value:
  Pb.from_int32(x)

def value.int64(+w: Pb.Word64) -> Pb.Value:
  Pb.from_int64(w)

def value.uint32(+x: U32) -> Pb.Value:
  Pb.from_uint32(x)

def value.uint64(+w: Pb.Word64) -> Pb.Value:
  Pb.from_uint64(w)

def value.sint32(+x: U32) -> Pb.Value:
  Pb.from_sint32(x)

def value.sint64(+w: Pb.Word64) -> Pb.Value:
  Pb.from_sint64(w)

def value.fixed32(+x: U32) -> Pb.Value:
  Pb.from_fixed32(x)

def value.fixed64(+w: Pb.Word64) -> Pb.Value:
  Pb.from_fixed64(w)

def value.sfixed32(+x: U32) -> Pb.Value:
  Pb.from_sfixed32(x)

def value.sfixed64(+w: Pb.Word64) -> Pb.Value:
  Pb.from_sfixed64(w)

def value.bool(+b: Bool) -> Pb.Value:
  Pb.from_bool(b)

def value.string(+s: String) -> Pb.Value:
  Pb.Blob{string.encode(s)}

def value.bytes(+xs: List<&2, U32>) -> Pb.Value:
  Pb.Blob{bytes.of_list(xs)}

def value.enum(+x: U32) -> Pb.Value:
  Pb.from_int32(x)

# A nested message: its fields, encoded.
def value.message(fs: List<&1, Pb.Field>) -> Pb.Value:
  Pb.Blob{encode(fs)}

# ------------------------------------------------------------------ readers

def read.double.fin(r: Result<&2, &1, String, Pb.Word64>) -> Result<&2, &1, String, F32>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{w}:
      Done{double.of_bits(w)}

def read.fixed64(v: Pb.Value) -> Result<&2, &1, String, Pb.Word64>:
  lift2(Pb.Word64, "protobuf: wire type mismatch for fixed64", Pb.to_fixed64(v))

def read.double(v: Pb.Value) -> Result<&2, &1, String, F32>:
  read.double.fin(read.fixed64(v))

def read.float(v: Pb.Value) -> Result<&2, &1, String, F32>:
  lift2(F32, "protobuf: wire type mismatch for float", Pb.to_float(v))

def read.int32(v: Pb.Value) -> Result<&2, &1, String, U32>:
  lift2(U32, "protobuf: wire type mismatch for int32", Pb.to_int32(v))

def read.int64(v: Pb.Value) -> Result<&2, &1, String, Pb.Word64>:
  lift2(Pb.Word64, "protobuf: wire type mismatch for int64", Pb.to_int64(v))

def read.uint32(v: Pb.Value) -> Result<&2, &1, String, U32>:
  lift2(U32, "protobuf: wire type mismatch for uint32", Pb.to_uint32(v))

def read.uint64(v: Pb.Value) -> Result<&2, &1, String, Pb.Word64>:
  lift2(Pb.Word64, "protobuf: wire type mismatch for uint64", Pb.to_uint64(v))

def read.sint32(v: Pb.Value) -> Result<&2, &1, String, U32>:
  lift2(U32, "protobuf: wire type mismatch for sint32", Pb.to_sint32(v))

def read.sint64(v: Pb.Value) -> Result<&2, &1, String, Pb.Word64>:
  lift2(Pb.Word64, "protobuf: wire type mismatch for sint64", Pb.to_sint64(v))

def read.fixed32(v: Pb.Value) -> Result<&2, &1, String, U32>:
  lift2(U32, "protobuf: wire type mismatch for fixed32", Pb.to_fixed32(v))

def read.sfixed32(v: Pb.Value) -> Result<&2, &1, String, U32>:
  lift2(U32, "protobuf: wire type mismatch for sfixed32", Pb.to_sfixed32(v))

def read.sfixed64(v: Pb.Value) -> Result<&2, &1, String, Pb.Word64>:
  lift2(Pb.Word64, "protobuf: wire type mismatch for sfixed64", Pb.to_sfixed64(v))

def read.bool(v: Pb.Value) -> Result<&2, &1, String, Bool>:
  lift2(Bool, "protobuf: wire type mismatch for bool", Pb.to_bool(v))

def read.enum(v: Pb.Value) -> Result<&2, &1, String, U32>:
  lift2(U32, "protobuf: wire type mismatch for enum", Pb.to_int32(v))

def read.string(v: Pb.Value) -> Result<&2, &1, String, String>:
  lift2(String, "protobuf: invalid string field (wire type or UTF-8)", Pb.to_string(v))

# The raw payload of a length-delimited field.
def read.blob(v: Pb.Value) -> Result<&2, &1, String, Bytes.Bytes>:
  lift1(Bytes.Bytes, "protobuf: wire type mismatch for length-delimited field", Pb.to_bytes(v))

def read.bytes.fin(r: Result<&2, &1, String, Bytes.Bytes>) -> Result<&2, &1, String, List<&2, U32>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{b}:
      Done{bytes.to_list(b)}

def read.bytes(v: Pb.Value) -> Result<&2, &1, String, List<&2, U32>>:
  read.bytes.fin(read.blob(v))

# A nested message's fields; decode them with the generated per-field fold.
def read.message(v: Pb.Value) -> Result<&2, &1, String, List<&1, Pb.Field>>:
  do Result<&2, &1, String, List<&1, Pb.Field>>:
    b : Bytes.Bytes <- read.blob(v)
    decode(b)

# --- repeated: conses onto acc (so acc is in REVERSE order; finish with Pbr.rev)

def rep.single(~T: Data, ~read: Pb.Value -> Result<&2, &1, String, T>, v: Pb.Value, acc: List<&2, T>) -> Result<&2, &1, String, List<&2, T>>:
  do Result<&2, &1, String, List<&2, T>>:
    x : T <- read(v)
    return x <> acc

def rep.vals(~T: Data, ~read: Pb.Value -> Result<&2, &1, String, T>, vs: List<&1, Pb.Value>, acc: List<&2, T>) -> Result<&2, &1, String, List<&2, T>>:
  match vs:
    case Nil{}:
      Done{acc}
    case Con{v, rest}:
      do Result<&2, &1, String, List<&2, T>>:
        x : T <- read(v)
        rep.vals(~T, ~read, rest, x <> acc)

def rep.packed(~T: Data, ~read: Pb.Value -> Result<&2, &1, String, T>, r: Result<&2, &1, Pb.Error, List<&1, Pb.Value>>, acc: List<&2, T>) -> Result<&2, &1, String, List<&2, T>>:
  match r:
    case Fail{e}:
      Fail{"protobuf: malformed packed field"}
    case Done{vs}:
      rep.vals(~T, ~read, vs, acc)

# wire: 0 varint, 1 fixed64, 5 fixed32 (the element encoding inside a packed blob).
def rep.read(~T: Data, ~read: Pb.Value -> Result<&2, &1, String, T>, +wire: U32, v: Pb.Value, acc: List<&2, T>) -> Result<&2, &1, String, List<&2, T>>:
  match v:
    case Pb.Blob{b}:
      rep.packed(~T, ~read, Pb.packed_decode(wire, b, max_size()), acc)
    case Pb.Varint{w}:
      rep.single(~T, ~read, Pb.Varint{w}, acc)
    case Pb.Fixed32{x}:
      rep.single(~T, ~read, Pb.Fixed32{x}, acc)
    case Pb.Fixed64{w}:
      rep.single(~T, ~read, Pb.Fixed64{w}, acc)
    case Pb.Group{fs}:
      Fail{"protobuf: unexpected group in repeated field"}

def read.repeated.double(v: Pb.Value, acc: List<&2, F32>) -> Result<&2, &1, String, List<&2, F32>>:
  rep.read(~F32, ~read.double, 1, v, acc)

def read.repeated.float(v: Pb.Value, acc: List<&2, F32>) -> Result<&2, &1, String, List<&2, F32>>:
  rep.read(~F32, ~read.float, 5, v, acc)

def read.repeated.int32(v: Pb.Value, acc: List<&2, U32>) -> Result<&2, &1, String, List<&2, U32>>:
  rep.read(~U32, ~read.int32, 0, v, acc)

def read.repeated.int64(v: Pb.Value, acc: List<&2, Pb.Word64>) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  rep.read(~Pb.Word64, ~read.int64, 0, v, acc)

def read.repeated.uint32(v: Pb.Value, acc: List<&2, U32>) -> Result<&2, &1, String, List<&2, U32>>:
  rep.read(~U32, ~read.uint32, 0, v, acc)

def read.repeated.uint64(v: Pb.Value, acc: List<&2, Pb.Word64>) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  rep.read(~Pb.Word64, ~read.uint64, 0, v, acc)

def read.repeated.sint32(v: Pb.Value, acc: List<&2, U32>) -> Result<&2, &1, String, List<&2, U32>>:
  rep.read(~U32, ~read.sint32, 0, v, acc)

def read.repeated.sint64(v: Pb.Value, acc: List<&2, Pb.Word64>) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  rep.read(~Pb.Word64, ~read.sint64, 0, v, acc)

def read.repeated.fixed32(v: Pb.Value, acc: List<&2, U32>) -> Result<&2, &1, String, List<&2, U32>>:
  rep.read(~U32, ~read.fixed32, 5, v, acc)

def read.repeated.fixed64(v: Pb.Value, acc: List<&2, Pb.Word64>) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  rep.read(~Pb.Word64, ~read.fixed64, 1, v, acc)

def read.repeated.sfixed32(v: Pb.Value, acc: List<&2, U32>) -> Result<&2, &1, String, List<&2, U32>>:
  rep.read(~U32, ~read.sfixed32, 5, v, acc)

def read.repeated.sfixed64(v: Pb.Value, acc: List<&2, Pb.Word64>) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  rep.read(~Pb.Word64, ~read.sfixed64, 1, v, acc)

def read.repeated.bool(v: Pb.Value, acc: List<&2, Bool>) -> Result<&2, &1, String, List<&2, Bool>>:
  rep.read(~Bool, ~read.bool, 0, v, acc)

def read.repeated.enum(v: Pb.Value, acc: List<&2, U32>) -> Result<&2, &1, String, List<&2, U32>>:
  rep.read(~U32, ~read.enum, 0, v, acc)

# strings and bytes are never packed: one element per field
def read.repeated.string(v: Pb.Value, acc: List<&2, String>) -> Result<&2, &1, String, List<&2, String>>:
  rep.single(~String, ~read.string, v, acc)

def read.repeated.bytes(v: Pb.Value, acc: List<&2, List<&2, U32>>) -> Result<&2, &1, String, List<&2, List<&2, U32>>>:
  rep.single(~List<&2, U32>, ~read.bytes, v, acc)

# ------------------------------------------------------------------ writers

def one(+n: U32, v: Pb.Value) -> List<&1, Pb.Field>:
  Con{Pb.Field{n, v}, Nil{}}

def skip.if(skip: Bool, +n: U32, v: Pb.Value) -> List<&1, Pb.Field>:
  match skip:
    case True{}:
      Nil{}
    case False{}:
      one(n, v)

# `field.K.always`: exactly one field (use for oneof members and proto3 `optional`).
def field.double.always(+n: U32, +f: F32) -> List<&1, Pb.Field>:
  one(n, value.double(f))

def field.float.always(+n: U32, +f: F32) -> List<&1, Pb.Field>:
  one(n, value.float(f))

def field.int32.always(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  one(n, value.int32(x))

def field.int64.always(+n: U32, w: Pb.Word64) -> List<&1, Pb.Field>:
  one(n, value.int64(w))

def field.uint32.always(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  one(n, value.uint32(x))

def field.uint64.always(+n: U32, w: Pb.Word64) -> List<&1, Pb.Field>:
  one(n, value.uint64(w))

def field.sint32.always(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  one(n, value.sint32(x))

def field.sint64.always(+n: U32, w: Pb.Word64) -> List<&1, Pb.Field>:
  one(n, value.sint64(w))

def field.fixed32.always(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  one(n, value.fixed32(x))

def field.fixed64.always(+n: U32, w: Pb.Word64) -> List<&1, Pb.Field>:
  one(n, value.fixed64(w))

def field.sfixed32.always(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  one(n, value.sfixed32(x))

def field.sfixed64.always(+n: U32, w: Pb.Word64) -> List<&1, Pb.Field>:
  one(n, value.sfixed64(w))

def field.bool.always(+n: U32, +b: Bool) -> List<&1, Pb.Field>:
  one(n, value.bool(b))

def field.string.always(+n: U32, +s: String) -> List<&1, Pb.Field>:
  one(n, value.string(s))

def field.bytes.always(+n: U32, xs: List<&2, U32>) -> List<&1, Pb.Field>:
  one(n, value.bytes(xs))

def field.enum.always(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  one(n, value.enum(x))

def field.message.always(+n: U32, fs: List<&1, Pb.Field>) -> List<&1, Pb.Field>:
  one(n, value.message(fs))

# A present singular message (an empty message is still emitted).
def field.message(+n: U32, fs: List<&1, Pb.Field>) -> List<&1, Pb.Field>:
  field.message.always(n, fs)

# `field.K`: omitted when x is the proto3 default (0, 0.0 with zero bits, false, "", empty bytes).
def field.double(+n: U32, +f: F32) -> List<&1, Pb.Field>:
  skip.if(U32.is_zero(F32.bits(f)), n, value.double(f))

def field.float(+n: U32, +f: F32) -> List<&1, Pb.Field>:
  skip.if(U32.is_zero(F32.bits(f)), n, value.float(f))

def field.int32(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  skip.if(U32.is_zero(x), n, value.int32(x))

def field.int64(+n: U32, +w: Pb.Word64) -> List<&1, Pb.Field>:
  skip.if(Pb.Word64.is_zero(w), n, value.int64(w))

def field.uint32(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  skip.if(U32.is_zero(x), n, value.uint32(x))

def field.uint64(+n: U32, +w: Pb.Word64) -> List<&1, Pb.Field>:
  skip.if(Pb.Word64.is_zero(w), n, value.uint64(w))

def field.sint32(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  skip.if(U32.is_zero(x), n, value.sint32(x))

def field.sint64(+n: U32, +w: Pb.Word64) -> List<&1, Pb.Field>:
  skip.if(Pb.Word64.is_zero(w), n, value.sint64(w))

def field.fixed32(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  skip.if(U32.is_zero(x), n, value.fixed32(x))

def field.fixed64(+n: U32, +w: Pb.Word64) -> List<&1, Pb.Field>:
  skip.if(Pb.Word64.is_zero(w), n, value.fixed64(w))

def field.sfixed32(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  skip.if(U32.is_zero(x), n, value.sfixed32(x))

def field.sfixed64(+n: U32, +w: Pb.Word64) -> List<&1, Pb.Field>:
  skip.if(Pb.Word64.is_zero(w), n, value.sfixed64(w))

def field.bool(+n: U32, +b: Bool) -> List<&1, Pb.Field>:
  skip.if(Bool.not(b), n, value.bool(b))

def field.string(+n: U32, +s: String) -> List<&1, Pb.Field>:
  skip.if(String.is_empty(s), n, value.string(s))

def field.bytes(+n: U32, +xs: List<&2, U32>) -> List<&1, Pb.Field>:
  skip.if(List.is_empty(&2, U32, xs), n, value.bytes(xs))

def field.enum(+n: U32, +x: U32) -> List<&1, Pb.Field>:
  skip.if(U32.is_zero(x), n, value.enum(x))

# --- repeated

def rep.pack.fin(+n: U32, r: Result<&2, &1, Pb.Error, Bytes.Bytes>) -> List<&1, Pb.Field>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{b}:
      one(n, Pb.Blob{b})

def rep.map(~T: Data, ~val: @+x: T -> Pb.Value, xs: List<&2, T>) -> List<&1, Pb.Value>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      val(h) <> rep.map(~T, ~val, t)

def rep.pack.go(~T: Data, ~val: @+x: T -> Pb.Value, +n: U32, xs: List<&2, T>) -> List<&1, Pb.Field>:
  rep.pack.fin(n, Pb.packed_encode(rep.map(~T, ~val, xs), max_size()))

def rep.pack(~T: Data, ~val: @+x: T -> Pb.Value, +n: U32, xs: List<&2, T>) -> List<&1, Pb.Field>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      rep.pack.go(~T, ~val, n, Con{h, t})

def rep.each(~T: Data, ~val: @+x: T -> Pb.Value, +n: U32, xs: List<&2, T>) -> List<&1, Pb.Field>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Pb.Field{n, val(h)} <> rep.each(~T, ~val, n, t)

# Packed for numeric, bool and enum kinds; [] for an empty list.
def field.repeated.double(+n: U32, xs: List<&2, F32>) -> List<&1, Pb.Field>:
  rep.pack(~F32, ~value.double, n, xs)

def field.repeated.float(+n: U32, xs: List<&2, F32>) -> List<&1, Pb.Field>:
  rep.pack(~F32, ~value.float, n, xs)

def field.repeated.int32(+n: U32, xs: List<&2, U32>) -> List<&1, Pb.Field>:
  rep.pack(~U32, ~value.int32, n, xs)

def field.repeated.int64(+n: U32, xs: List<&2, Pb.Word64>) -> List<&1, Pb.Field>:
  rep.pack(~Pb.Word64, ~value.int64, n, xs)

def field.repeated.uint32(+n: U32, xs: List<&2, U32>) -> List<&1, Pb.Field>:
  rep.pack(~U32, ~value.uint32, n, xs)

def field.repeated.uint64(+n: U32, xs: List<&2, Pb.Word64>) -> List<&1, Pb.Field>:
  rep.pack(~Pb.Word64, ~value.uint64, n, xs)

def field.repeated.sint32(+n: U32, xs: List<&2, U32>) -> List<&1, Pb.Field>:
  rep.pack(~U32, ~value.sint32, n, xs)

def field.repeated.sint64(+n: U32, xs: List<&2, Pb.Word64>) -> List<&1, Pb.Field>:
  rep.pack(~Pb.Word64, ~value.sint64, n, xs)

def field.repeated.fixed32(+n: U32, xs: List<&2, U32>) -> List<&1, Pb.Field>:
  rep.pack(~U32, ~value.fixed32, n, xs)

def field.repeated.fixed64(+n: U32, xs: List<&2, Pb.Word64>) -> List<&1, Pb.Field>:
  rep.pack(~Pb.Word64, ~value.fixed64, n, xs)

def field.repeated.sfixed32(+n: U32, xs: List<&2, U32>) -> List<&1, Pb.Field>:
  rep.pack(~U32, ~value.sfixed32, n, xs)

def field.repeated.sfixed64(+n: U32, xs: List<&2, Pb.Word64>) -> List<&1, Pb.Field>:
  rep.pack(~Pb.Word64, ~value.sfixed64, n, xs)

def field.repeated.bool(+n: U32, xs: List<&2, Bool>) -> List<&1, Pb.Field>:
  rep.pack(~Bool, ~value.bool, n, xs)

def field.repeated.enum(+n: U32, xs: List<&2, U32>) -> List<&1, Pb.Field>:
  rep.pack(~U32, ~value.enum, n, xs)

# One field per element.
def field.repeated.string(+n: U32, xs: List<&2, String>) -> List<&1, Pb.Field>:
  rep.each(~String, ~value.string, n, xs)

def field.repeated.bytes(+n: U32, xs: List<&2, List<&2, U32>>) -> List<&1, Pb.Field>:
  rep.each(~List<&2, U32>, ~value.bytes, n, xs)

# items: each element's fields (e.g. from List.map over the generated to-fields function).
def field.repeated.message(+n: U32, items: List<&1, List<&1, Pb.Field>>) -> List<&1, Pb.Field>:
  match items:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      cat(field.message(n, h), field.repeated.message(n, t))
