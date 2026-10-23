# F32-dependent tests for src/pb.bend (F32.bits / F32 literals only run natively; IO main compiles).
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-protobuf@0.1.0.0/protobuf.bend as Pb
import ../src/pb.bend as Pbr

def check(name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      String.append("PASS ", name)
    case False{}:
      String.append("\"FAIL ", name)

def hx(+s: String) -> Bytes.Bytes:
  Maybe.default(&1, Bytes.Bytes, Bytes.from_hex(String.concat(String.split(s, ' '))), Bytes.new(0))

def enc(fs: List<&1, Pb.Field>) -> String:
  Bytes.to_hex(Pbr.encode(fs))

def first.go(fs: List<&1, Pb.Field>) -> Pb.Value:
  match fs:
    case Nil{}:
      Pb.Varint{Pb.Word64{0, 0}}
    case Con{Pb.Field{n, v}, t}:
      v

def first(r: Result<&2, &1, String, List<&1, Pb.Field>>) -> Pb.Value:
  match r:
    case Fail{e}:
      Pb.Varint{Pb.Word64{0, 0}}
    case Done{fs}:
      first.go(fs)

def bits(r: Result<&2, &1, String, F32>) -> U32:
  match r:
    case Fail{e}:
      0
    case Done{f}:
      F32.bits(f)

def dbits.go(xs: List<&2, F32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      String.concat([U32.show(F32.bits(h)), ",", dbits.go(t)])

def dbits(r: Result<&2, &1, String, List<&2, F32>>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{xs}:
      dbits.go(Pbr.rev(F32, xs))

def results() -> List<&2, String>:
  [
    check("double 1.5 field 1", String.eq(enc(Pbr.field.double(1, 1.5)), "09000000000000f83f")),
    check("double 0 omitted", String.eq(enc(Pbr.field.double(1, 0.0)), "")),
    check("double 0 always", String.eq(enc(Pbr.field.double.always(1, 0.0)), "090000000000000000")),
    check("double -0.0 is not default", String.eq(enc(Pbr.field.double(1, F32.neg(0.0))), "090000000000000080")),
    check("double -2 field 2", String.eq(enc(Pbr.field.double(2, F32.neg(2.0))), "1100000000000000c0")),
    check("float 1.5 field 1", String.eq(enc(Pbr.field.float(1, 1.5)), "0d0000c03f")),
    check("float 0 omitted", String.eq(enc(Pbr.field.float(1, 0.0)), "")),
    check("float -1.5", String.eq(enc(Pbr.field.float(1, F32.neg(1.5))), "0d0000c0bf")),
    check("packed float", String.eq(enc(Pbr.field.repeated.float(3, [1.5, 1.5])), "1a080000c03f0000c03f")),
    check("packed double", String.eq(enc(Pbr.field.repeated.double(3, [1.5])), "1a08000000000000f83f")),
    check("read.double 1.5", U32.is_eq(bits(Pbr.read.double(first(Pbr.decode(hx("09000000000000f83f"))))), F32.bits(1.5))),
    check("read.float 1.5", U32.is_eq(bits(Pbr.read.float(first(Pbr.decode(hx("0d0000c03f"))))), F32.bits(1.5))),
    check("read.double wrong wire type", U32.is_eq(bits(Pbr.read.double(first(Pbr.decode(hx("0d0000c03f"))))), 0)),
    check("read.double rounds to f32", U32.is_eq(bits(Pbr.read.double(first(Pbr.decode(hx("09 9a9999999999b93f"))))), F32.bits(0.1))),
    check("repeated double packed", String.eq(dbits(Pbr.read.repeated.double(first(Pbr.decode(hx("1a08000000000000f83f"))), [])), "1069547520,")),
    check("repeated float unpacked", String.eq(dbits(Pbr.read.repeated.float(first(Pbr.decode(hx("0d0000c03f"))), [])), "1069547520,")),
    check("f32 bits round trip", U32.is_eq(Pbr.f32.bits(Pbr.f32.of_bits(1069547520)), 1069547520)),
    check("double bits of 1.5", String.eq(Pbr.word64.show_u(Pbr.double.bits(1.5)), "4609434218613702656")),
    check("double of_bits 1.5", U32.is_eq(F32.bits(Pbr.double.of_bits(Pb.Word64{1073217536, 0})), F32.bits(1.5)))
  ]

def main() -> IO(Unit):
  List.for_each(~&2, ~String, ~IO.print, results())
