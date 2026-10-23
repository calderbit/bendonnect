# Golden-vector test for the generated kitchen-sink module (tests/codegen/proto/kitchen.proto).
#
# For every vector written by the Go program (tests/codegen/golden):
#   1. decode the binary, re-encode, and compare bytes with Go's;
#   2. decode the canonical protojson, re-encode it to binary and compare with Go's bytes;
#   3. print "bin <name> <hex>" and "json <name> <json>" lines for Go to parse back (run.sh).
# Run through tests/codegen/run.sh (it generates the vectors and the Bend code first).
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-encoding@0.4.0.0/encoding.bend as Enc
import ../../src/pb.bend as Pbr
import ./gen/bend/kitchen_pb.bend as K
import ./vectors/vectors.bend as V

# ---- hex <-> bytes

def hex.val(+c: U32) -> U32:
  Bool.pick(U32, U32.is_lt(c, 58), (c - 48 : U32), (c - 87 : U32))

def hex.digit(+n: U32) -> U32:
  Bool.pick(U32, U32.is_lt(n, 10), (n + 48 : U32), (n + 87 : U32))

def ch(c: U32) -> String:
  SCon{Chr{c}, SNil{}}

def hex.dec(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{+a}, r1}:
      match r1:
        case SNil{}:
          Nil{}
        case SCon{Chr{+b}, r2}:
          Con{(hex.val(a) * 16 + hex.val(b) : U32), hex.dec(r2)}

def hex.enc(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, rest}:
      ch(hex.digit((x >> 4n : U32))) ++ ch(hex.digit((x .&. 15 : U32))) ++ hex.enc(rest)

def hex.of_bytes(b: Bytes.Bytes) -> String:
  hex.enc(Pbr.bytes.to_list(b))

def text(b: Bytes.Bytes) -> String:
  Enc.utf8.decode(b)

# ---- the check, generic over the message type (templates: each instance is closed)

def verdict(ok: Bool, what: String) -> String:
  match ok:
    case True{}:
      "PASS " ++ what
    case False{}:
      "FAIL " ++ what

def run.j(~T: Data, ~dp: Bytes.Bytes -> Result<&2, &1, String, T>, ~ep: T -> Bytes.Bytes,
          ~dj: Bytes.Bytes -> Result<&2, &1, String, T>, ~ej: T -> Bytes.Bytes,
          +name: String, +hex: String, +m: T, r: Result<&2, &1, String, T>) -> List<&2, String>:
  match r:
    case Fail{e}:
      ["FAIL json decode " ++ name ++ ": " ++ e]
    case Done{+mj}:
      [verdict(String.eq(hex.of_bytes(ep(m)), hex), "binary roundtrip " ++ name),
       verdict(String.eq(hex.of_bytes(ep(mj)), hex), "json -> binary " ++ name),
       "bin " ++ name ++ " " ++ hex.of_bytes(ep(m)),
       "json " ++ name ++ " " ++ text(ej(m))]

def run.p(~T: Data, ~dp: Bytes.Bytes -> Result<&2, &1, String, T>, ~ep: T -> Bytes.Bytes,
          ~dj: Bytes.Bytes -> Result<&2, &1, String, T>, ~ej: T -> Bytes.Bytes,
          +name: String, +hex: String, +json: String, r: Result<&2, &1, String, T>) -> List<&2, String>:
  match r:
    case Fail{e}:
      ["FAIL binary decode " ++ name ++ ": " ++ e]
    case Done{+m}:
      run.j(~T, ~dp, ~ep, ~dj, ~ej, name, hex, m, dj(Enc.utf8.encode(json)))

def run(~T: Data, ~dp: Bytes.Bytes -> Result<&2, &1, String, T>, ~ep: T -> Bytes.Bytes,
        ~dj: Bytes.Bytes -> Result<&2, &1, String, T>, ~ej: T -> Bytes.Bytes, v: V.Vec) -> List<&2, String>:
  match v:
    case V.Vec{+name, +hex, +json}:
      run.p(~T, ~dp, ~ep, ~dj, ~ej, name, hex, json, dp(Pbr.bytes.of_list(hex.dec(hex))))

def report(ls: List<&2, String>) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{l, rest}:
      do IO<Unit>:
        IO.print(l)
        report(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    report(run(~K.Scalars, ~K.Scalars.decode_proto, ~K.Scalars.encode_proto, ~K.Scalars.decode_json, ~K.Scalars.encode_json, V.vec.empty()))
    report(run(~K.Scalars, ~K.Scalars.decode_proto, ~K.Scalars.encode_proto, ~K.Scalars.decode_json, ~K.Scalars.encode_json, V.vec.scalars()))
    report(run(~K.Scalars, ~K.Scalars.decode_proto, ~K.Scalars.encode_proto, ~K.Scalars.decode_json, ~K.Scalars.encode_json, V.vec.scalars_small()))
    report(run(~K.Repeats, ~K.Repeats.decode_proto, ~K.Repeats.encode_proto, ~K.Repeats.decode_json, ~K.Repeats.encode_json, V.vec.repeats()))
    report(run(~K.Outer, ~K.Outer.decode_proto, ~K.Outer.encode_proto, ~K.Outer.decode_json, ~K.Outer.encode_json, V.vec.outer()))
    report(run(~K.Tree, ~K.Tree.decode_proto, ~K.Tree.encode_proto, ~K.Tree.decode_json, ~K.Tree.encode_json, V.vec.tree()))
    report(run(~K.Maps, ~K.Maps.decode_proto, ~K.Maps.encode_proto, ~K.Maps.decode_json, ~K.Maps.encode_json, V.vec.maps()))
    report(run(~K.Choice, ~K.Choice.decode_proto, ~K.Choice.encode_proto, ~K.Choice.decode_json, ~K.Choice.encode_json, V.vec.choice_none()))
    report(run(~K.Choice, ~K.Choice.decode_proto, ~K.Choice.encode_proto, ~K.Choice.decode_json, ~K.Choice.encode_json, V.vec.choice_number()))
    report(run(~K.Choice, ~K.Choice.decode_proto, ~K.Choice.encode_proto, ~K.Choice.decode_json, ~K.Choice.encode_json, V.vec.choice_zero()))
    report(run(~K.Choice, ~K.Choice.decode_proto, ~K.Choice.encode_proto, ~K.Choice.decode_json, ~K.Choice.encode_json, V.vec.choice_text()))
    report(run(~K.Choice, ~K.Choice.decode_proto, ~K.Choice.encode_proto, ~K.Choice.decode_json, ~K.Choice.encode_json, V.vec.choice_scalars()))
    report(run(~K.Choice, ~K.Choice.decode_proto, ~K.Choice.encode_proto, ~K.Choice.decode_json, ~K.Choice.encode_json, V.vec.choice_color()))
    report(run(~K.Choice, ~K.Choice.decode_proto, ~K.Choice.encode_proto, ~K.Choice.decode_json, ~K.Choice.encode_json, V.vec.choice_raw()))
    report(run(~K.Optionals, ~K.Optionals.decode_proto, ~K.Optionals.encode_proto, ~K.Optionals.decode_json, ~K.Optionals.encode_json, V.vec.optionals_unset()))
    report(run(~K.Optionals, ~K.Optionals.decode_proto, ~K.Optionals.encode_proto, ~K.Optionals.decode_json, ~K.Optionals.encode_json, V.vec.optionals_zero()))
    report(run(~K.Optionals, ~K.Optionals.decode_proto, ~K.Optionals.encode_proto, ~K.Optionals.decode_json, ~K.Optionals.encode_json, V.vec.optionals_set()))
    report(run(~K.Keywords, ~K.Keywords.decode_proto, ~K.Keywords.encode_proto, ~K.Keywords.decode_json, ~K.Keywords.encode_json, V.vec.keywords()))
    report(run(~K.Kitchen, ~K.Kitchen.decode_proto, ~K.Kitchen.encode_proto, ~K.Kitchen.decode_json, ~K.Kitchen.encode_json, V.vec.kitchen()))
