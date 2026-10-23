# proto3 JSON runtime for generated code (alias Pj). Pure. Reference: docs/runtime.md.
#
# Writing: accumulate `List<&1, Bytes & Json.Val>` in REVERSE (each put conses) and finish with `Pj.obj`.
# Reading: `Pj.fields(v)` gives the object's entries as `List<&1, String & Json.Val>`; `Pj.take`
# removes one field (by lowerCamel json name or original proto name) and answers its value
# (Json.Null{} when absent, which every reader maps to the default).
# Readers answer Result<&2, &1, String, T>.
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-encoding@0.4.0.0/encoding.bend as Enc
import bend-kit-json@0.6.1.1/json.bend as Json
import bend-kit-protobuf@0.1.0.0/protobuf.bend as Pb
import ./b64.bend as B64
import ./pb.bend as Pbr

# ------------------------------------------------------------------ text helpers

def i32.show(+x: U32) -> String:
  Bool.pick(String, U32.is_ge(x, 2147483648), String.append("-", U32.show((0 - x : U32))), U32.show(x))

def num(+s: String) -> Json.Val:
  Json.Num{Bytes.from_string(s)}

def str(+s: String) -> Json.Val:
  Json.Str{Enc.utf8.encode(s)}

# Finite F32 -> JSON number; NaN / +-Infinity -> the strings the proto3 JSON spec names.
def f32.fin(kind: U32, +f: F32) -> Json.Val:
  match kind:
    case 0:
      num(F32.show(f))
    case 1:
      str("NaN")
    case 2:
      str("Infinity")
    case _:
      str("-Infinity")

def f32.kind(+b: U32) -> U32:
  Bool.pick(U32, U32.is_ne(((b >> 23n) .&. 255 : U32), 255), 0,
  Bool.pick(U32, U32.is_ne((b .&. 8388607 : U32), 0), 1,
  Bool.pick(U32, U32.is_zero((b >> 31n : U32)), 2, 3)))

# ------------------------------------------------------------------ values

def val.double(+f: F32) -> Json.Val:
  f32.fin(f32.kind(F32.bits(f)), f)

def val.float(+f: F32) -> Json.Val:
  f32.fin(f32.kind(F32.bits(f)), f)

def val.int32(+x: U32) -> Json.Val:
  num(i32.show(x))

def val.sint32(+x: U32) -> Json.Val:
  num(i32.show(x))

def val.sfixed32(+x: U32) -> Json.Val:
  num(i32.show(x))

def val.uint32(+x: U32) -> Json.Val:
  num(U32.show(x))

def val.fixed32(+x: U32) -> Json.Val:
  num(U32.show(x))

# 64-bit integers are quoted decimal strings.
def val.int64(+w: Pb.Word64) -> Json.Val:
  str(Pbr.word64.show_s(w))

def val.sint64(+w: Pb.Word64) -> Json.Val:
  str(Pbr.word64.show_s(w))

def val.sfixed64(+w: Pb.Word64) -> Json.Val:
  str(Pbr.word64.show_s(w))

def val.uint64(+w: Pb.Word64) -> Json.Val:
  str(Pbr.word64.show_u(w))

def val.fixed64(+w: Pb.Word64) -> Json.Val:
  str(Pbr.word64.show_u(w))

def val.bool(+b: Bool) -> Json.Val:
  Json.Flag{b}

def val.string(+s: String) -> Json.Val:
  str(s)

# Standard base64 with padding.
def val.bytes(+xs: List<&2, U32>) -> Json.Val:
  str(B64.encode_std(Pbr.bytes.of_list(xs)))

# name(n) is the enum value's name; "" (unknown number) prints as the number.
def val.enum.go(+s: String, +x: U32) -> Json.Val:
  Bool.pick(Json.Val, String.is_empty(s), num(i32.show(x)), str(s))

def val.enum(~name: @+n: U32 -> String, +x: U32) -> Json.Val:
  val.enum.go(name(x), x)

# ------------------------------------------------------------------ writers

def entry(+key: String, v: Json.Val) -> Bytes.Bytes & Json.Val:
  (Enc.utf8.encode(key), v)

def put.always.v(+name: String, v: Json.Val, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  Con{entry(name, v), acc}

def put.skip(skip: Bool, +name: String, v: Json.Val, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  match skip:
    case True{}:
      acc
    case False{}:
      put.always.v(name, v, acc)

# Finishes an accumulator built by put.*: restores field order.
def obj(acc: List<&1, Bytes.Bytes & Json.Val>) -> Json.Val:
  Json.Obj{List.reverse(&1, Bytes.Bytes & Json.Val, acc)}

# `put.K.always`: always emitted (oneof members, proto3 optional).
def put.double.always(+name: String, +f: F32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.double(f), acc)

def put.float.always(+name: String, +f: F32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.float(f), acc)

def put.int32.always(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.int32(x), acc)

def put.sint32.always(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.sint32(x), acc)

def put.sfixed32.always(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.sfixed32(x), acc)

def put.uint32.always(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.uint32(x), acc)

def put.fixed32.always(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.fixed32(x), acc)

def put.int64.always(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.int64(w), acc)

def put.sint64.always(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.sint64(w), acc)

def put.sfixed64.always(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.sfixed64(w), acc)

def put.uint64.always(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.uint64(w), acc)

def put.fixed64.always(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.fixed64(w), acc)

def put.bool.always(+name: String, +b: Bool, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.bool(b), acc)

def put.string.always(+name: String, +s: String, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.string(s), acc)

def put.bytes.always(+name: String, +xs: List<&2, U32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, val.bytes(xs), acc)

def put.enum.always(~name: @+n: U32 -> String, +jn: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(jn, val.enum(~name, x), acc)

# A present message: v is the generated Msg.to_json(m).
def put.message(+name: String, v: Json.Val, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.always.v(name, v, acc)

# `put.K`: omitted when x is the proto3 default.
def put.double(+name: String, +f: F32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(U32.is_zero(F32.bits(f)), name, val.double(f), acc)

def put.float(+name: String, +f: F32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(U32.is_zero(F32.bits(f)), name, val.float(f), acc)

def put.int32(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(U32.is_zero(x), name, val.int32(x), acc)

def put.sint32(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(U32.is_zero(x), name, val.sint32(x), acc)

def put.sfixed32(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(U32.is_zero(x), name, val.sfixed32(x), acc)

def put.uint32(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(U32.is_zero(x), name, val.uint32(x), acc)

def put.fixed32(+name: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(U32.is_zero(x), name, val.fixed32(x), acc)

def put.int64(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(Pb.Word64.is_zero(w), name, val.int64(w), acc)

def put.sint64(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(Pb.Word64.is_zero(w), name, val.sint64(w), acc)

def put.sfixed64(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(Pb.Word64.is_zero(w), name, val.sfixed64(w), acc)

def put.uint64(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(Pb.Word64.is_zero(w), name, val.uint64(w), acc)

def put.fixed64(+name: String, +w: Pb.Word64, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(Pb.Word64.is_zero(w), name, val.fixed64(w), acc)

def put.bool(+name: String, +b: Bool, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(Bool.not(b), name, val.bool(b), acc)

def put.string(+name: String, +s: String, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(String.is_empty(s), name, val.string(s), acc)

def put.bytes(+name: String, +xs: List<&2, U32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(List.is_empty(&2, U32, xs), name, val.bytes(xs), acc)

def put.enum(~name: @+n: U32 -> String, +jn: String, +x: U32, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  put.skip(U32.is_zero(x), jn, val.enum(~name, x), acc)

# --- repeated: omitted when empty

def rep.arr(~T: Data, ~val: @+x: T -> Json.Val, xs: List<&2, T>) -> List<&1, Json.Val>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      val(h) <> rep.arr(~T, ~val, t)

def rep.put(~T: Data, ~val: @+x: T -> Json.Val, +name: String, xs: List<&2, T>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      put.always.v(name, Json.Arr{rep.arr(~T, ~val, Con{h, t})}, acc)

def put.repeated.double(+name: String, xs: List<&2, F32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~F32, ~val.double, name, xs, acc)

def put.repeated.float(+name: String, xs: List<&2, F32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~F32, ~val.float, name, xs, acc)

def put.repeated.int32(+name: String, xs: List<&2, U32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~U32, ~val.int32, name, xs, acc)

def put.repeated.sint32(+name: String, xs: List<&2, U32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~U32, ~val.sint32, name, xs, acc)

def put.repeated.sfixed32(+name: String, xs: List<&2, U32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~U32, ~val.sfixed32, name, xs, acc)

def put.repeated.uint32(+name: String, xs: List<&2, U32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~U32, ~val.uint32, name, xs, acc)

def put.repeated.fixed32(+name: String, xs: List<&2, U32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~U32, ~val.fixed32, name, xs, acc)

def put.repeated.int64(+name: String, xs: List<&2, Pb.Word64>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~Pb.Word64, ~val.int64, name, xs, acc)

def put.repeated.sint64(+name: String, xs: List<&2, Pb.Word64>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~Pb.Word64, ~val.sint64, name, xs, acc)

def put.repeated.sfixed64(+name: String, xs: List<&2, Pb.Word64>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~Pb.Word64, ~val.sfixed64, name, xs, acc)

def put.repeated.uint64(+name: String, xs: List<&2, Pb.Word64>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~Pb.Word64, ~val.uint64, name, xs, acc)

def put.repeated.fixed64(+name: String, xs: List<&2, Pb.Word64>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~Pb.Word64, ~val.fixed64, name, xs, acc)

def put.repeated.bool(+name: String, xs: List<&2, Bool>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~Bool, ~val.bool, name, xs, acc)

def put.repeated.string(+name: String, xs: List<&2, String>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~String, ~val.string, name, xs, acc)

def put.repeated.bytes(+name: String, xs: List<&2, List<&2, U32>>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~List<&2, U32>, ~val.bytes, name, xs, acc)

def put.repeated.enum(~name: @+n: U32 -> String, +jn: String, xs: List<&2, U32>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  rep.put(~U32, ~(+x => val.enum(~name, x)), jn, xs, acc)

# vs: each element's Msg.to_json(m); omitted when empty.
def put.repeated.message(+name: String, vs: List<&1, Json.Val>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  match vs:
    case Nil{}:
      acc
    case Con{h, t}:
      put.always.v(name, Json.Arr{Con{h, t}}, acc)

# map<K,V>: entries built with Pj.entry(Pj.key.K(k), value); omitted when empty.
def put.map(+name: String, entries: List<&1, Bytes.Bytes & Json.Val>, acc: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  match entries:
    case Nil{}:
      acc
    case Con{h, t}:
      put.always.v(name, Json.Obj{Con{h, t}}, acc)

# map keys as JSON object keys
def key.int32(+x: U32) -> String:
  i32.show(x)

def key.sint32(+x: U32) -> String:
  i32.show(x)

def key.sfixed32(+x: U32) -> String:
  i32.show(x)

def key.uint32(+x: U32) -> String:
  U32.show(x)

def key.fixed32(+x: U32) -> String:
  U32.show(x)

def key.int64(+w: Pb.Word64) -> String:
  Pbr.word64.show_s(w)

def key.sint64(+w: Pb.Word64) -> String:
  Pbr.word64.show_s(w)

def key.sfixed64(+w: Pb.Word64) -> String:
  Pbr.word64.show_s(w)

def key.uint64(+w: Pb.Word64) -> String:
  Pbr.word64.show_u(w)

def key.fixed64(+w: Pb.Word64) -> String:
  Pbr.word64.show_u(w)

def key.bool(+b: Bool) -> String:
  Bool.pick(String, b, "true", "false")

def key.string(+s: String) -> String:
  s

# ------------------------------------------------------------------ encode / parse

def encode(v: Json.Val) -> Bytes.Bytes:
  Json.encode.bytes(v)

def parse.fin(m: Maybe<&1, Json.Val>) -> Result<&2, &1, String, Json.Val>:
  match m:
    case None{}:
      Fail{"invalid JSON"}
    case Some{v}:
      Done{v}

def parse(b: Bytes.Bytes) -> Result<&2, &1, String, Json.Val>:
  parse.fin(Json.parse.bytes(b))

# ------------------------------------------------------------------ reading objects

def fields.go(kvs: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, String & Json.Val>:
  match kvs:
    case Nil{}:
      Nil{}
    case Con{(k, v), t}:
      Con{(Enc.utf8.decode(k), v), fields.go(t)}

# The entries of a JSON object, keys decoded. A non-object (including null) is an error;
# for singular message fields test for null first with Pj.read.opt.
def fields(v: Json.Val) -> Result<&2, &1, String, List<&1, String & Json.Val>>:
  match v:
    case Json.Obj{kvs}:
      Done{fields.go(kvs)}
    case Json.Null{}:
      Fail{"expected a JSON object, got null"}
    case Json.Flag{on}:
      Fail{"expected a JSON object, got a boolean"}
    case Json.Num{s}:
      Fail{"expected a JSON object, got a number"}
    case Json.Str{s}:
      Fail{"expected a JSON object, got a string"}
    case Json.Arr{xs}:
      Fail{"expected a JSON object, got an array"}

# A map field's entries (keys as strings); null is an empty map.
def read.map.entries(v: Json.Val) -> Result<&2, &1, String, List<&1, String & Json.Val>>:
  match v:
    case Json.Obj{kvs}:
      Done{fields.go(kvs)}
    case Json.Null{}:
      Done{Nil{}}
    case Json.Flag{on}:
      Fail{"expected a JSON object for a map field"}
    case Json.Num{s}:
      Fail{"expected a JSON object for a map field"}
    case Json.Str{s}:
      Fail{"expected a JSON object for a map field"}
    case Json.Arr{xs}:
      Fail{"expected a JSON object for a map field"}

# One accepted JSON key (json_name or proto_name) of a field and that field's number.
type JKey is Data:
  JKey{name: String, num: U32}

# The number of the field whose accepted key equals k, or 0 for an unknown key. Typical use:
# `M.set(m, Pj.dispatch(k, M.json_keys()), v)` where M.set destructures m, then matches on its U32 parameter.
def dispatch(+k: String, table: List<&2, JKey>) -> U32:
  match table:
    case Nil{}:
      0
    case Con{JKey{+name, +num}, t}:
      Bool.pick(U32, String.eq(k, name), num, dispatch(k, t))

def is_key(+k: String, +jn: String, +pn: String) -> Bool:
  String.eq(k, jn) || String.eq(k, pn)

def take.step(hit: Bool, k: String, v: Json.Val, r: Json.Val & List<&1, String & Json.Val>) -> Json.Val & List<&1, String & Json.Val>:
  match hit:
    case True{}:
      (f, rest) = r
      (v, rest)
    case False{}:
      (f, rest) = r
      (f, Con{(k, v), rest})

def take.go(+jn: String, +pn: String, kvs: List<&1, String & Json.Val>) -> Json.Val & List<&1, String & Json.Val>:
  match kvs:
    case Nil{}:
      (Json.Null{}, Nil{})
    case Con{(+k, v), t}:
      take.step(is_key(k, jn, pn), k, v, take.go(jn, pn, t))

# Removes the field named json_name or proto_name and answers its value (Json.Null{} if absent,
# which every Pj.read.* maps to the default) beside the remaining entries. Unknown keys simply stay
# in the rest and can be dropped. A later duplicate of a matched key is removed too.
def take(kvs: List<&1, String & Json.Val>, +json_name: String, +proto_name: String) -> Json.Val & List<&1, String & Json.Val>:
  take.go(json_name, proto_name, kvs)

# ------------------------------------------------------------------ scalar readers

def lift.m(-T: Data, m: Maybe<&2, T>, what: String) -> Result<&2, &1, String, T>:
  match m:
    case None{}:
      Fail{what}
    case Some{x}:
      Done{x}

def int32.fin(m: Maybe<&2, Pb.Word64>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{w}:
      Pb.Word64{+h, +l} = w
      Bool.pick(Maybe<&2, U32>, U32.is_eq(h, (0 - (l >> 31n) : U32)), Some{l}, None{})

def uint32.fin(m: Maybe<&2, Pb.Word64>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{w}:
      Pb.Word64{+h, +l} = w
      Bool.pick(Maybe<&2, U32>, U32.is_zero(h), Some{l}, None{})

# Decimal text (optionally negative) that fits int32 / uint32 / int64 / uint64.
def parse.int32(+s: String) -> Maybe<&2, U32>:
  int32.fin(Pbr.word64.read_s(s))

def parse.uint32(+s: String) -> Maybe<&2, U32>:
  uint32.fin(Pbr.word64.read_u(s))

def parse.int64(+s: String) -> Maybe<&2, Pb.Word64>:
  Pbr.word64.read_s(s)

def parse.uint64(+s: String) -> Maybe<&2, Pb.Word64>:
  Pbr.word64.read_u(s)

def parse.float(+s: String) -> Maybe<&2, F32>:
  Bool.pick(Maybe<&2, F32>, String.eq(s, "NaN"), Some{Pbr.f32.of_bits(2143289344)},
  Bool.pick(Maybe<&2, F32>, String.eq(s, "Infinity"), Some{Pbr.f32.of_bits(2139095040)},
  Bool.pick(Maybe<&2, F32>, String.eq(s, "-Infinity"), Some{Pbr.f32.of_bits(4286578688)},
  F32.read(s))))

# null -> dflt; number or string -> parse(text); anything else is an error.
def read.scalar(~T: Data, ~parse: @+s: String -> Maybe<&2, T>, +dflt: T, +what: String, v: Json.Val) -> Result<&2, &1, String, T>:
  match v:
    case Json.Null{}:
      Done{dflt}
    case Json.Num{b}:
      lift.m(T, parse(Bytes.to_string(b)), what)
    case Json.Str{b}:
      lift.m(T, parse(Enc.utf8.decode(b)), what)
    case Json.Flag{on}:
      Fail{what}
    case Json.Arr{xs}:
      Fail{what}
    case Json.Obj{kvs}:
      Fail{what}

def read.int32(v: Json.Val) -> Result<&2, &1, String, U32>:
  read.scalar(~U32, ~parse.int32, 0, "expected an int32", v)

def read.sint32(v: Json.Val) -> Result<&2, &1, String, U32>:
  read.scalar(~U32, ~parse.int32, 0, "expected an int32", v)

def read.sfixed32(v: Json.Val) -> Result<&2, &1, String, U32>:
  read.scalar(~U32, ~parse.int32, 0, "expected an int32", v)

def read.uint32(v: Json.Val) -> Result<&2, &1, String, U32>:
  read.scalar(~U32, ~parse.uint32, 0, "expected a uint32", v)

def read.fixed32(v: Json.Val) -> Result<&2, &1, String, U32>:
  read.scalar(~U32, ~parse.uint32, 0, "expected a uint32", v)

def read.int64(v: Json.Val) -> Result<&2, &1, String, Pb.Word64>:
  read.scalar(~Pb.Word64, ~parse.int64, Pb.Word64{0, 0}, "expected an int64", v)

def read.sint64(v: Json.Val) -> Result<&2, &1, String, Pb.Word64>:
  read.scalar(~Pb.Word64, ~parse.int64, Pb.Word64{0, 0}, "expected an int64", v)

def read.sfixed64(v: Json.Val) -> Result<&2, &1, String, Pb.Word64>:
  read.scalar(~Pb.Word64, ~parse.int64, Pb.Word64{0, 0}, "expected an int64", v)

def read.uint64(v: Json.Val) -> Result<&2, &1, String, Pb.Word64>:
  read.scalar(~Pb.Word64, ~parse.uint64, Pb.Word64{0, 0}, "expected a uint64", v)

def read.fixed64(v: Json.Val) -> Result<&2, &1, String, Pb.Word64>:
  read.scalar(~Pb.Word64, ~parse.uint64, Pb.Word64{0, 0}, "expected a uint64", v)

def read.float(v: Json.Val) -> Result<&2, &1, String, F32>:
  read.scalar(~F32, ~parse.float, 0.0, "expected a float", v)

def read.double(v: Json.Val) -> Result<&2, &1, String, F32>:
  read.scalar(~F32, ~parse.float, 0.0, "expected a double", v)

def read.bool(v: Json.Val) -> Result<&2, &1, String, Bool>:
  match v:
    case Json.Null{}:
      Done{False{}}
    case Json.Flag{on}:
      Done{on}
    case Json.Num{s}:
      Fail{"expected a boolean"}
    case Json.Str{s}:
      Fail{"expected a boolean"}
    case Json.Arr{xs}:
      Fail{"expected a boolean"}
    case Json.Obj{kvs}:
      Fail{"expected a boolean"}

def read.string(v: Json.Val) -> Result<&2, &1, String, String>:
  match v:
    case Json.Null{}:
      Done{""}
    case Json.Str{b}:
      Done{Enc.utf8.decode(b)}
    case Json.Flag{on}:
      Fail{"expected a string"}
    case Json.Num{s}:
      Fail{"expected a string"}
    case Json.Arr{xs}:
      Fail{"expected a string"}
    case Json.Obj{kvs}:
      Fail{"expected a string"}

def bytes.fin(m: Maybe<&1, Bytes.Bytes>) -> Result<&2, &1, String, List<&2, U32>>:
  match m:
    case None{}:
      Fail{"invalid base64"}
    case Some{b}:
      Done{Pbr.bytes.to_list(b)}

# Standard or URL-safe base64, padded or not.
def read.bytes(v: Json.Val) -> Result<&2, &1, String, List<&2, U32>>:
  match v:
    case Json.Null{}:
      Done{Nil{}}
    case Json.Str{b}:
      bytes.fin(B64.decode(Enc.utf8.decode(b)))
    case Json.Flag{on}:
      Fail{"expected a base64 string"}
    case Json.Num{s}:
      Fail{"expected a base64 string"}
    case Json.Arr{xs}:
      Fail{"expected a base64 string"}
    case Json.Obj{kvs}:
      Fail{"expected a base64 string"}

# Enum by name (from_name = the generated E.from_name) or by number; null -> 0.
def read.enum(~from_name: @+s: String -> Maybe<&2, U32>, v: Json.Val) -> Result<&2, &1, String, U32>:
  match v:
    case Json.Null{}:
      Done{0}
    case Json.Str{b}:
      lift.m(U32, from_name(Enc.utf8.decode(b)), "unknown enum value")
    case Json.Num{b}:
      lift.m(U32, parse.int32(Bytes.to_string(b)), "invalid enum number")
    case Json.Flag{on}:
      Fail{"expected an enum name or number"}
    case Json.Arr{xs}:
      Fail{"expected an enum name or number"}
    case Json.Obj{kvs}:
      Fail{"expected an enum name or number"}

def opt.some(~T: Data, ~read: Json.Val -> Result<&2, &1, String, T>, v: Json.Val) -> Result<&2, &1, String, Maybe<&2, T>>:
  do Result<&2, &1, String, Maybe<&2, T>>:
    x : T <- read(v)
    return Some{x}

# Presence-aware read for optional scalars, oneof members and singular messages:
# null/absent -> None, otherwise Some(read(v)).
def read.opt(~T: Data, ~read: Json.Val -> Result<&2, &1, String, T>, v: Json.Val) -> Result<&2, &1, String, Maybe<&2, T>>:
  match v:
    case Json.Null{}:
      Done{None{}}
    case Json.Flag{on}:
      opt.some(~T, ~read, Json.Flag{on})
    case Json.Num{s}:
      opt.some(~T, ~read, Json.Num{s})
    case Json.Str{s}:
      opt.some(~T, ~read, Json.Str{s})
    case Json.Arr{xs}:
      opt.some(~T, ~read, Json.Arr{xs})
    case Json.Obj{kvs}:
      opt.some(~T, ~read, Json.Obj{kvs})

# ------------------------------------------------------------------ repeated and maps

def rep.read(~T: Data, ~read: Json.Val -> Result<&2, &1, String, T>, xs: List<&1, Json.Val>) -> Result<&2, &1, String, List<&2, T>>:
  match xs:
    case Nil{}:
      Done{Nil{}}
    case Con{h, t}:
      do Result<&2, &1, String, List<&2, T>>:
        x : T <- read(h)
        rest : List<&2, T> <- rep.read(~T, ~read, t)
        return x <> rest

# null -> []; array -> each element through read (for messages pass ~Msg.from_json).
def read.repeated(~T: Data, ~read: Json.Val -> Result<&2, &1, String, T>, v: Json.Val) -> Result<&2, &1, String, List<&2, T>>:
  match v:
    case Json.Null{}:
      Done{Nil{}}
    case Json.Arr{xs}:
      rep.read(~T, ~read, xs)
    case Json.Flag{on}:
      Fail{"expected an array"}
    case Json.Num{s}:
      Fail{"expected an array"}
    case Json.Str{s}:
      Fail{"expected an array"}
    case Json.Obj{kvs}:
      Fail{"expected an array"}

def read.repeated.double(v: Json.Val) -> Result<&2, &1, String, List<&2, F32>>:
  read.repeated(~F32, ~read.double, v)

def read.repeated.float(v: Json.Val) -> Result<&2, &1, String, List<&2, F32>>:
  read.repeated(~F32, ~read.float, v)

def read.repeated.int32(v: Json.Val) -> Result<&2, &1, String, List<&2, U32>>:
  read.repeated(~U32, ~read.int32, v)

def read.repeated.sint32(v: Json.Val) -> Result<&2, &1, String, List<&2, U32>>:
  read.repeated(~U32, ~read.sint32, v)

def read.repeated.sfixed32(v: Json.Val) -> Result<&2, &1, String, List<&2, U32>>:
  read.repeated(~U32, ~read.sfixed32, v)

def read.repeated.uint32(v: Json.Val) -> Result<&2, &1, String, List<&2, U32>>:
  read.repeated(~U32, ~read.uint32, v)

def read.repeated.fixed32(v: Json.Val) -> Result<&2, &1, String, List<&2, U32>>:
  read.repeated(~U32, ~read.fixed32, v)

def read.repeated.int64(v: Json.Val) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  read.repeated(~Pb.Word64, ~read.int64, v)

def read.repeated.sint64(v: Json.Val) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  read.repeated(~Pb.Word64, ~read.sint64, v)

def read.repeated.sfixed64(v: Json.Val) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  read.repeated(~Pb.Word64, ~read.sfixed64, v)

def read.repeated.uint64(v: Json.Val) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  read.repeated(~Pb.Word64, ~read.uint64, v)

def read.repeated.fixed64(v: Json.Val) -> Result<&2, &1, String, List<&2, Pb.Word64>>:
  read.repeated(~Pb.Word64, ~read.fixed64, v)

def read.repeated.bool(v: Json.Val) -> Result<&2, &1, String, List<&2, Bool>>:
  read.repeated(~Bool, ~read.bool, v)

def read.repeated.string(v: Json.Val) -> Result<&2, &1, String, List<&2, String>>:
  read.repeated(~String, ~read.string, v)

def read.repeated.bytes(v: Json.Val) -> Result<&2, &1, String, List<&2, List<&2, U32>>>:
  read.repeated(~List<&2, U32>, ~read.bytes, v)

def read.repeated.enum(~from_name: @+s: String -> Maybe<&2, U32>, v: Json.Val) -> Result<&2, &1, String, List<&2, U32>>:
  read.repeated(~U32, ~(v => read.enum(~from_name, v)), v)

# map keys (JSON object keys are strings)
def read.key.int32(+s: String) -> Result<&2, &1, String, U32>:
  lift.m(U32, parse.int32(s), "invalid int32 map key")

def read.key.sint32(+s: String) -> Result<&2, &1, String, U32>:
  lift.m(U32, parse.int32(s), "invalid int32 map key")

def read.key.sfixed32(+s: String) -> Result<&2, &1, String, U32>:
  lift.m(U32, parse.int32(s), "invalid int32 map key")

def read.key.uint32(+s: String) -> Result<&2, &1, String, U32>:
  lift.m(U32, parse.uint32(s), "invalid uint32 map key")

def read.key.fixed32(+s: String) -> Result<&2, &1, String, U32>:
  lift.m(U32, parse.uint32(s), "invalid uint32 map key")

def read.key.int64(+s: String) -> Result<&2, &1, String, Pb.Word64>:
  lift.m(Pb.Word64, parse.int64(s), "invalid int64 map key")

def read.key.sint64(+s: String) -> Result<&2, &1, String, Pb.Word64>:
  lift.m(Pb.Word64, parse.int64(s), "invalid int64 map key")

def read.key.sfixed64(+s: String) -> Result<&2, &1, String, Pb.Word64>:
  lift.m(Pb.Word64, parse.int64(s), "invalid int64 map key")

def read.key.uint64(+s: String) -> Result<&2, &1, String, Pb.Word64>:
  lift.m(Pb.Word64, parse.uint64(s), "invalid uint64 map key")

def read.key.fixed64(+s: String) -> Result<&2, &1, String, Pb.Word64>:
  lift.m(Pb.Word64, parse.uint64(s), "invalid uint64 map key")

def read.key.bool(+s: String) -> Result<&2, &1, String, Bool>:
  Bool.pick(Result<&2, &1, String, Bool>, String.eq(s, "true"), Done{True{}},
  Bool.pick(Result<&2, &1, String, Bool>, String.eq(s, "false"), Done{False{}}, Fail{"invalid bool map key"}))

def read.key.string(+s: String) -> Result<&2, &1, String, String>:
  Done{s}

def map.go(~K: Data, ~V: Data, ~E: Data, ~key: @+s: String -> Result<&2, &1, String, K>, ~value: Json.Val -> Result<&2, &1, String, V>, ~mk: @+k: K -> @+v: V -> E, es: List<&1, String & Json.Val>) -> Result<&2, &1, String, List<&2, E>>:
  match es:
    case Nil{}:
      Done{Nil{}}
    case Con{(k, v), t}:
      do Result<&2, &1, String, List<&2, E>>:
        kk : K <- key(k)
        vv : V <- value(v)
        rest : List<&2, E> <- map.go(~K, ~V, ~E, ~key, ~value, ~mk, t)
        return mk(kk, vv) <> rest

# Whole map field in one call: keys via ~Pj.read.key.K, values via ~Pj.read.V (or ~Msg.from_json),
# entries built by mk (e.g. ~(+k => +v => Entry{k, v})). null -> [].
def read.map(~K: Data, ~V: Data, ~E: Data, ~key: @+s: String -> Result<&2, &1, String, K>, ~value: Json.Val -> Result<&2, &1, String, V>, ~mk: @+k: K -> @+v: V -> E, v: Json.Val) -> Result<&2, &1, String, List<&2, E>>:
  do Result<&2, &1, String, List<&2, E>>:
    es : List<&1, String & Json.Val> <- read.map.entries(v)
    map.go(~K, ~V, ~E, ~key, ~value, ~mk, es)
