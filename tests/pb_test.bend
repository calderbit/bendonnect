# Tests for src/pb.bend (proto binary runtime). `bend tests/pb_test.bend` prints PASS/FAIL lines.
# main is IO so the pure code runs compiled (the checker normalizer takes minutes on this file);
# failures print as `"FAIL name` so tests/run_all.sh's grep for '"FAIL' catches them.
# F32-dependent cases (F32.bits is native-only) live in tests/pbfloat_test.bend.
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

# hex of the encoded field list
def enc(fs: List<&1, Pb.Field>) -> String:
  Bytes.to_hex(Pbr.encode(fs))

def ints(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      String.concat([U32.show(h), ",", ints(t)])

def r_u32(r: Result<&2, &1, String, U32>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{x}:
      U32.show(x)

def r_w(r: Result<&2, &1, String, Pb.Word64>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{w}:
      Pbr.word64.show_s(w)

def r_wu(r: Result<&2, &1, String, Pb.Word64>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{w}:
      Pbr.word64.show_u(w)

def r_str(r: Result<&2, &1, String, String>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{s}:
      s

def m_wu(m: Maybe<&2, Pb.Word64>) -> String:
  match m:
    case None{}:
      "fail"
    case Some{w}:
      Pbr.word64.show_u(w)

def m_ws(m: Maybe<&2, Pb.Word64>) -> String:
  match m:
    case None{}:
      "fail"
    case Some{w}:
      Pbr.word64.show_s(w)

def r_bool(r: Result<&2, &1, String, Bool>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{b}:
      Bool.show(b)

def r_ints(r: Result<&2, &1, String, List<&2, U32>>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{xs}:
      ints(Pbr.rev(U32, xs))

def r_bytes(r: Result<&2, &1, String, List<&2, U32>>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{xs}:
      ints(xs)

def is_fail(r: Result<&2, &1, String, List<&1, Pb.Field>>) -> Bool:
  match r:
    case Fail{e}:
      True{}
    case Done{fs}:
      False{}

# first field of a decoded message
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

def first_num.go(fs: List<&1, Pb.Field>) -> U32:
  match fs:
    case Nil{}:
      0
    case Con{Pb.Field{n, v}, t}:
      n

def first_num(r: Result<&2, &1, String, List<&1, Pb.Field>>) -> U32:
  match r:
    case Fail{e}:
      0
    case Done{fs}:
      first_num.go(fs)

# A message type decoded the way generated code does: fold over the fields, dispatch on the number.
type Hi is Data:
  Hi{name: String, n: U32, tags: List<&2, U32>}

def Hi.set(+m: Hi, +num: U32, v: Pb.Value) -> Result<&2, &1, String, Hi>:
  Hi{+name, +n, +tags} = m
  match num:
    case 1:
      do Result<&2, &1, String, Hi>:
        s : String <- Pbr.read.string(v)
        return Hi{s, n, tags}
    case 2:
      do Result<&2, &1, String, Hi>:
        x : U32 <- Pbr.read.int32(v)
        return Hi{name, x, tags}
    case 3:
      do Result<&2, &1, String, Hi>:
        ts : List<&2, U32> <- Pbr.read.repeated.int32(v, tags)
        return Hi{name, n, ts}
    case _:
      Done{Hi{name, n, tags}}

def Hi.fold(fs: List<&1, Pb.Field>, m: Hi) -> Result<&2, &1, String, Hi>:
  match fs:
    case Nil{}:
      Done{m}
    case Con{Pb.Field{num, v}, t}:
      do Result<&2, &1, String, Hi>:
        m2 : Hi <- Hi.set(m, num, v)
        Hi.fold(t, m2)

def Hi.fin(r: Result<&2, &1, String, Hi>) -> Result<&2, &1, String, Hi>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{Hi{name, n, tags}}:
      Done{Hi{name, n, Pbr.rev(U32, tags)}}

def Hi.decode_fields(r: Result<&2, &1, String, List<&1, Pb.Field>>) -> Result<&2, &1, String, Hi>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{fs}:
      Hi.fin(Hi.fold(fs, Hi{"", 0, Nil{}}))

def Hi.decode(b: Bytes.Bytes) -> Result<&2, &1, String, Hi>:
  Hi.decode_fields(Pbr.decode(b))

def Hi.show(r: Result<&2, &1, String, Hi>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{Hi{name, n, tags}}:
      String.concat([name, "|", U32.show(n), "|", ints(tags)])

def Hi.encode(+m: Hi) -> Bytes.Bytes:
  Hi{+name, +n, +tags} = m
  Pbr.encode(Pbr.cat.all([Pbr.field.string(1, name), Pbr.field.int32(2, n), Pbr.field.repeated.int32(3, tags)]))

def results() -> List<&2, String>:
  [
    # --- scalar field encodings
    check("int32 -1 is 10 bytes", String.eq(enc(Pbr.field.int32(1, 4294967295)), "08ffffffffffffffffff01")),
    check("int32 150", String.eq(enc(Pbr.field.int32(1, 150)), "089601")),
    check("int32 0 omitted", String.eq(enc(Pbr.field.int32(1, 0)), "")),
    check("int32 0 always", String.eq(enc(Pbr.field.int32.always(1, 0)), "0800")),
    check("sint32 -1", String.eq(enc(Pbr.field.sint32(1, 4294967295)), "0801")),
    check("sint32 1", String.eq(enc(Pbr.field.sint32(1, 1)), "0802")),
    check("sint32 max", String.eq(enc(Pbr.field.sint32(1, 2147483647)), "08feffffff0f")),
    check("sint32 min", String.eq(enc(Pbr.field.sint32(1, 2147483648)), "08ffffffff0f")),
    check("uint32 max", String.eq(enc(Pbr.field.uint32(2, 4294967295)), "10ffffffff0f")),
    check("string hi", String.eq(enc(Pbr.field.string(1, "hi")), "0a026869")),
    check("string empty omitted", String.eq(enc(Pbr.field.string(1, "")), "")),
    check("string empty always", String.eq(enc(Pbr.field.string.always(1, "")), "0a00")),
    check("string utf8", String.eq(enc(Pbr.field.string(1, "é€😀")), "0a09c3a9e282acf09f9880")),
    check("bool true", String.eq(enc(Pbr.field.bool(1, True{})), "0801")),
    check("bool false omitted", String.eq(enc(Pbr.field.bool(1, False{})), "")),
    check("bool false always", String.eq(enc(Pbr.field.bool.always(1, False{})), "0800")),
    check("bytes", String.eq(enc(Pbr.field.bytes(2, [1, 2, 3])), "1203010203")),
    check("bytes empty omitted", String.eq(enc(Pbr.field.bytes(2, [])), "")),
    check("fixed32", String.eq(enc(Pbr.field.fixed32(1, 1)), "0d01000000")),
    check("sfixed32 -1", String.eq(enc(Pbr.field.sfixed32(1, 4294967295)), "0dffffffff")),
    check("fixed64", String.eq(enc(Pbr.field.fixed64(2, Pb.Word64{1, 2})), "110200000001000000")),
    check("sfixed64 -2", String.eq(enc(Pbr.field.sfixed64(2, Pb.Word64{4294967295, 4294967294})), "11feffffffffffffff")),
    check("int64 -1", String.eq(enc(Pbr.field.int64(1, Pb.Word64{4294967295, 4294967295})), "08ffffffffffffffffff01")),
    check("int64 min", String.eq(enc(Pbr.field.int64(1, Pb.Word64{2147483648, 0})), "0880808080808080808001")),
    check("uint64 max", String.eq(enc(Pbr.field.uint64(1, Pb.Word64{4294967295, 4294967295})), "08ffffffffffffffffff01")),
    check("sint64 -1", String.eq(enc(Pbr.field.sint64(1, Pb.Word64{4294967295, 4294967295})), "0801")),
    check("sint64 min", String.eq(enc(Pbr.field.sint64(1, Pb.Word64{2147483648, 0})), "08ffffffffffffffffff01")),
    check("int64 0 omitted", String.eq(enc(Pbr.field.int64(1, Pb.Word64{0, 0})), "")),
    check("enum 2", String.eq(enc(Pbr.field.enum(5, 2)), "2802")),
    check("enum -1", String.eq(enc(Pbr.field.enum(5, 4294967295)), "28ffffffffffffffffff01")),
    check("enum 0 always", String.eq(enc(Pbr.field.enum.always(5, 0)), "2800")),
    # --- repeated
    check("packed int32 [1,2,3] field 4", String.eq(enc(Pbr.field.repeated.int32(4, [1, 2, 3])), "2203010203")),
    check("packed empty omitted", String.eq(enc(Pbr.field.repeated.int32(4, [])), "")),
    check("packed fixed32", String.eq(enc(Pbr.field.repeated.fixed32(1, [1, 2])), "0a080100000002000000")),
    check("packed bool", String.eq(enc(Pbr.field.repeated.bool(1, [True{}, False{}, True{}])), "0a03010001")),
    check("packed sint32", String.eq(enc(Pbr.field.repeated.sint32(1, [4294967295, 1])), "0a020102")),
    check("packed uint64", String.eq(enc(Pbr.field.repeated.uint64(1, [Pb.Word64{0, 1}, Pb.Word64{0, 300}])), "0a0301ac02")),
    check("repeated string", String.eq(enc(Pbr.field.repeated.string(2, ["a", "bc"])), "12016112026263")),
    check("repeated bytes", String.eq(enc(Pbr.field.repeated.bytes(2, [[1], [2, 3]])), "12010112020203")),
    # --- messages
    check("nested message", String.eq(enc(Pbr.field.message(3, Pbr.field.int32(1, 150))), "1a03089601")),
    check("empty nested message present", String.eq(enc(Pbr.field.message(3, [])), "1a00")),
    check("repeated message", String.eq(enc(Pbr.field.repeated.message(1, [Pbr.field.int32(1, 1), Pbr.field.int32(1, 2)])), "0a0208010a020802")),
    check("cat.all order", String.eq(enc(Pbr.cat.all([Pbr.field.int32(1, 1), Pbr.field.string(2, "x"), Pbr.field.int32(3, 3)])), "08011201781803")),
    # --- decoding scalars
    check("read.int32 -1", String.eq(r_u32(Pbr.read.int32(first(Pbr.decode(hx("08ffffffffffffffffff01"))))), "4294967295")),
    check("read.int32 150", String.eq(r_u32(Pbr.read.int32(first(Pbr.decode(hx("089601"))))), "150")),
    check("read.sint32 -1", String.eq(r_u32(Pbr.read.sint32(first(Pbr.decode(hx("0801"))))), "4294967295")),
    check("read.sint32 min", String.eq(r_u32(Pbr.read.sint32(first(Pbr.decode(hx("08ffffffff0f"))))), "2147483648")),
    check("read.uint32 max", String.eq(r_u32(Pbr.read.uint32(first(Pbr.decode(hx("08ffffffff0f"))))), "4294967295")),
    check("read.int64 min", String.eq(r_w(Pbr.read.int64(first(Pbr.decode(hx("0880808080808080808001"))))), "-9223372036854775808")),
    check("read.uint64 max", String.eq(r_wu(Pbr.read.uint64(first(Pbr.decode(hx("08ffffffffffffffffff01"))))), "18446744073709551615")),
    check("read.sint64 min", String.eq(r_w(Pbr.read.sint64(first(Pbr.decode(hx("08ffffffffffffffffff01"))))), "-9223372036854775808")),
    check("read.fixed64", String.eq(r_wu(Pbr.read.fixed64(first(Pbr.decode(hx("110200000001000000"))))), "4294967298")),
    check("read.sfixed64 -2", String.eq(r_w(Pbr.read.sfixed64(first(Pbr.decode(hx("11feffffffffffffff"))))), "-2")),
    check("read.sfixed32 -1", String.eq(r_u32(Pbr.read.sfixed32(first(Pbr.decode(hx("0dffffffff"))))), "4294967295")),
    check("read.fixed32", String.eq(r_u32(Pbr.read.fixed32(first(Pbr.decode(hx("0d01000000"))))), "1")),
    check("read.bool true", String.eq(r_bool(Pbr.read.bool(first(Pbr.decode(hx("0801"))))), "True")),
    check("read.bool 2 is true", String.eq(r_bool(Pbr.read.bool(first(Pbr.decode(hx("0802"))))), "True")),
    check("read.bool false", String.eq(r_bool(Pbr.read.bool(first(Pbr.decode(hx("0800"))))), "False")),
    check("read.string hi", String.eq(r_str(Pbr.read.string(first(Pbr.decode(hx("0a026869"))))), "hi")),
    check("read.string utf8", String.eq(r_str(Pbr.read.string(first(Pbr.decode(hx("0a09c3a9e282acf09f9880"))))), "é€😀")),
    check("read.string invalid utf8 fails", String.eq(r_str(Pbr.read.string(first(Pbr.decode(hx("0a02c328"))))), "fail")),
    check("read.string wrong wire type fails", String.eq(r_str(Pbr.read.string(first(Pbr.decode(hx("0801"))))), "fail")),
    check("read.int32 wrong wire type fails", String.eq(r_u32(Pbr.read.int32(first(Pbr.decode(hx("0a026869"))))), "fail")),
    check("read.bytes", String.eq(r_bytes(Pbr.read.bytes(first(Pbr.decode(hx("1203010203"))))), "1,2,3,")),
    check("read.enum", String.eq(r_u32(Pbr.read.enum(first(Pbr.decode(hx("2802"))))), "2")),
    check("field number decoded", U32.is_eq(first_num(Pbr.decode(hx("2802"))), 5)),
    # --- repeated reading: packed, unpacked, mixed, appending to acc
    check("repeated packed", String.eq(r_ints(Pbr.read.repeated.int32(first(Pbr.decode(hx("2203010203"))), [])), "1,2,3,")),
    check("repeated single", String.eq(r_ints(Pbr.read.repeated.int32(first(Pbr.decode(hx("2007"))), [])), "7,")),
    check("repeated acc is reversed", String.eq(r_ints(Pbr.read.repeated.int32(first(Pbr.decode(hx("2203010203"))), [9])), "9,1,2,3,")),
    check("repeated packed truncated fails", String.eq(r_ints(Pbr.read.repeated.int32(first(Pbr.decode(hx("220180"))), [])), "fail")),
    check("repeated fixed32 packed", String.eq(r_ints(Pbr.read.repeated.fixed32(first(Pbr.decode(hx("0a080100000002000000"))), [])), "1,2,")),
    check("repeated fixed32 single", String.eq(r_ints(Pbr.read.repeated.fixed32(first(Pbr.decode(hx("0d03000000"))), [])), "3,")),
    check("repeated sint32 packed", String.eq(r_ints(Pbr.read.repeated.sint32(first(Pbr.decode(hx("0a020102"))), [])), "4294967295,1,")),
    check("repeated enum packed", String.eq(r_ints(Pbr.read.repeated.enum(first(Pbr.decode(hx("0a03010203"))), [])), "1,2,3,")),
    # --- whole-message fold, like generated code
    check("fold basic", String.eq(Hi.show(Hi.decode(hx("0a026869109601"))), "hi|150|")),
    check("fold skips unknown field", String.eq(Hi.show(Hi.decode(hx("0a026869f806011007"))), "hi|7|")),
    check("fold skips unknown length-delimited", String.eq(Hi.show(Hi.decode(hx("a2060378797a1005"))), "|5|")),
    check("fold last scalar wins", String.eq(Hi.show(Hi.decode(hx("10011002"))), "|2|")),
    check("fold mixed packed + unpacked repeated", String.eq(Hi.show(Hi.decode(hx("1a02010218031a0104"))), "|0|1,2,3,4,")),
    check("fold wrong wire type fails", String.eq(Hi.show(Hi.decode(hx("0801"))), "fail")),
    check("fold empty message", String.eq(Hi.show(Hi.decode(hx(""))), "|0|")),
    check("encode/decode round trip", String.eq(Hi.show(Hi.decode(Hi.encode(Hi{"abc", 42, [5, 6, 7]}))), "abc|42|5,6,7,")),
    check("encode of defaults is empty", String.eq(Bytes.to_hex(Hi.encode(Hi{"", 0, []})), "")),
    # --- raw decode errors
    check("truncated length fails", is_fail(Pbr.decode(hx("0a0568")))),
    check("truncated varint fails", is_fail(Pbr.decode(hx("0880")))),
    check("field number 0 fails", is_fail(Pbr.decode(hx("0001")))),
    check("nested message decode", String.eq(r_u32(Pbr.read.int32(first(Pbr.read.message(first(Pbr.decode(hx("1a03089601"))))))), "150")),
    check("nested message truncated fails", is_fail(Pbr.read.message(first(Pbr.decode(hx("1a0208"))))) ),
    # --- word64
    check("show_u max", String.eq(Pbr.word64.show_u(Pb.Word64{4294967295, 4294967295}), "18446744073709551615")),
    check("show_s -1", String.eq(Pbr.word64.show_s(Pb.Word64{4294967295, 4294967295}), "-1")),
    check("show_s min", String.eq(Pbr.word64.show_s(Pb.Word64{2147483648, 0}), "-9223372036854775808")),
    check("show_s max", String.eq(Pbr.word64.show_s(Pb.Word64{2147483647, 4294967295}), "9223372036854775807")),
    check("show_u 0", String.eq(Pbr.word64.show_u(Pb.Word64{0, 0}), "0")),
    check("show_u 2^32", String.eq(Pbr.word64.show_u(Pb.Word64{1, 0}), "4294967296")),
    check("show_u 10^19", String.eq(Pbr.word64.show_u(Pb.Word64{2328306436, 2313682944}), "10000000000000000000")),
    check("read_u max", String.eq(m_wu(Pbr.word64.read_u("18446744073709551615")), "18446744073709551615")),
    check("read_u overflow", String.eq(m_wu(Pbr.word64.read_u("18446744073709551616")), "fail")),
    check("read_u junk", String.eq(m_wu(Pbr.word64.read_u("12x")), "fail")),
    check("read_u empty", String.eq(m_wu(Pbr.word64.read_u("")), "fail")),
    check("read_u minus rejected", String.eq(m_wu(Pbr.word64.read_u("-1")), "fail")),
    check("read_s min", String.eq(m_ws(Pbr.word64.read_s("-9223372036854775808")), "-9223372036854775808")),
    check("read_s max", String.eq(m_ws(Pbr.word64.read_s("9223372036854775807")), "9223372036854775807")),
    check("read_s max+1 fails", String.eq(m_ws(Pbr.word64.read_s("9223372036854775808")), "fail")),
    check("read_s min-1 fails", String.eq(m_ws(Pbr.word64.read_s("-9223372036854775809")), "fail")),
    check("read_s -1", String.eq(m_ws(Pbr.word64.read_s("-1")), "-1")),
    check("read_s lone minus fails", String.eq(m_ws(Pbr.word64.read_s("-")), "fail")),
    check("read_s 0", String.eq(m_ws(Pbr.word64.read_s("0")), "0")),
    # --- zigzag / helpers
    check("zigzag32 -1", U32.is_eq(Pbr.zigzag32(4294967295), 1)),
    check("zigzag32 min", U32.is_eq(Pbr.zigzag32(2147483648), 4294967295)),
    check("unzigzag32 3", U32.is_eq(Pbr.unzigzag32(3), 4294967294)),
    check("word64.of_i32 -2", String.eq(Pbr.word64.show_s(Pbr.word64.of_i32(4294967294)), "-2")),
    check("word64.neg 1", String.eq(Pbr.word64.show_s(Pbr.word64.neg(Pb.Word64{0, 1})), "-1")),
    check("word64.neg 2^32", String.eq(Pbr.word64.show_s(Pbr.word64.neg(Pb.Word64{1, 0})), "-4294967296")),
    check("bytes round trip", String.eq(ints(Pbr.bytes.to_list(Pbr.bytes.of_list([0, 1, 255, 128]))), "0,1,255,128,")),
    # --- double / float bit conversion (pure parts)
    check("double bits of f32 1.5", String.eq(Pbr.word64.show_u(Pbr.double.of_f32bits(1069547520)), "4609434218613702656")),
    check("f32 bits of double 1.5", U32.is_eq(Pbr.double.f32bits(Pb.Word64{1073217536, 0}), 1069547520)),
    check("f32 bits of double 0.1 rounds", U32.is_eq(Pbr.double.f32bits(Pb.Word64{1069128089, 2576980378}), 1036831949)),
    check("f32 bits of huge double is inf", U32.is_eq(Pbr.double.f32bits(Pb.Word64{2117592124, 0}), 2139095040)),
    check("f32 bits of tiny double is 0", U32.is_eq(Pbr.double.f32bits(Pb.Word64{27618847, 0}), 0)),
    check("f32 subnormal 1e-45", U32.is_eq(Pbr.double.f32bits(Pb.Word64{916455424, 0}), 1))
  ]

def main() -> IO(Unit):
  List.for_each(~&2, ~String, ~IO.print, results())
