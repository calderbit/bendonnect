# Tests for src/pbjson.bend (proto3 JSON runtime). `bend tests/pbjson_test.bend` prints PASS/FAIL lines.
# IO main: F32 printing/parsing only runs natively. Failures print as `"FAIL name` (see run_all.sh).
# `Pt` below is a hand-written model of what protoc-gen-bend emits (fold over entries + dispatch).
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-encoding@0.4.0.0/encoding.bend as Enc
import bend-kit-json@0.6.1.1/json.bend as Json
import bend-kit-protobuf@0.1.0.0/protobuf.bend as Pb
import ../src/pb.bend as Pbr
import ../src/pbjson.bend as Pj

def check(name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      String.append("PASS ", name)
    case False{}:
      String.append("\"FAIL ", name)

def text(v: Json.Val) -> String:
  Enc.utf8.decode(Pj.encode(v))

def lit(+s: String) -> Bytes.Bytes:
  Enc.utf8.encode(s)

# parse a JSON literal (Null{} when invalid)
def pv.fin(m: Maybe<&1, Json.Val>) -> Json.Val:
  match m:
    case None{}:
      Json.Null{}
    case Some{v}:
      v

def pv(+s: String) -> Json.Val:
  pv.fin(Json.parse.bytes(lit(s)))

def ints(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      String.concat([U32.show(h), ",", ints(t)])

def strs(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      String.concat([h, ",", strs(t)])

def r_u32(r: Result<&2, &1, String, U32>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{x}:
      U32.show(x)

def r_i64(r: Result<&2, &1, String, Pb.Word64>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{w}:
      Pbr.word64.show_s(w)

def r_f(r: Result<&2, &1, String, F32>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{f}:
      F32.show(f)

def r_bool(r: Result<&2, &1, String, Bool>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{b}:
      Bool.show(b)

def r_str(r: Result<&2, &1, String, String>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{s}:
      s

def r_list(r: Result<&2, &1, String, List<&2, U32>>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{xs}:
      ints(xs)

def r_strs(r: Result<&2, &1, String, List<&2, String>>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{xs}:
      strs(xs)

def r_opt.go(m: Maybe<&2, U32>) -> String:
  match m:
    case None{}:
      "none"
    case Some{x}:
      U32.show(x)

def r_opt(r: Result<&2, &1, String, Maybe<&2, U32>>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{m}:
      r_opt.go(m)

# ---- enum Color {RED=0; GREEN=1; BLUE=2}
def Color.name(+n: U32) -> String:
  match n:
    case 0:
      "RED"
    case 1:
      "GREEN"
    case 2:
      "BLUE"
    case _:
      ""

def Color.from_name(+s: String) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, String.eq(s, "RED"), Some{0},
  Bool.pick(Maybe<&2, U32>, String.eq(s, "GREEN"), Some{1},
  Bool.pick(Maybe<&2, U32>, String.eq(s, "BLUE"), Some{2}, None{})))

# ---- message Pt
type Pt is Data:
  Pt{user_name: String, age: U32, id: Pb.Word64, tags: List<&2, String>, color: U32, data: List<&2, U32>, score: F32, ok: Bool, nums: List<&2, Pb.Word64>}

def Pt.default() -> Pt:
  Pt{"", 0, Pb.Word64{0, 0}, [], 0, [], 0.0, False{}, []}

def Pt.to_json(+m: Pt) -> Json.Val:
  Pt{+user_name, +age, +id, +tags, +color, +data, +score, +ok, +nums} = m
  Pj.obj(Pj.put.repeated.int64("nums", nums, Pj.put.bool("ok", ok, Pj.put.float("score", score, Pj.put.bytes("data", data, Pj.put.enum(~Color.name, "color", color, Pj.put.repeated.string("tags", tags, Pj.put.int64("id", id, Pj.put.int32("age", age, Pj.put.string("userName", user_name, Nil{})))))))))) 

def Pt.json_keys() -> List<&2, Pj.JKey>:
  [Pj.JKey{"userName", 1}, Pj.JKey{"user_name", 1}, Pj.JKey{"age", 2}, Pj.JKey{"id", 3}, Pj.JKey{"tags", 4}, Pj.JKey{"color", 5}, Pj.JKey{"data", 6}, Pj.JKey{"score", 7}, Pj.JKey{"ok", 8}, Pj.JKey{"nums", 9}]

def Pt.json_set(+m: Pt, +num: U32, v: Json.Val) -> Result<&2, &1, String, Pt>:
  Pt{+user_name, +age, +id, +tags, +color, +data, +score, +ok, +nums} = m
  match num:
    case 1:
      do Result<&2, &1, String, Pt>:
        x : String <- Pj.read.string(v)
        return Pt{x, age, id, tags, color, data, score, ok, nums}
    case 2:
      do Result<&2, &1, String, Pt>:
        x : U32 <- Pj.read.int32(v)
        return Pt{user_name, x, id, tags, color, data, score, ok, nums}
    case 3:
      do Result<&2, &1, String, Pt>:
        x : Pb.Word64 <- Pj.read.int64(v)
        return Pt{user_name, age, x, tags, color, data, score, ok, nums}
    case 4:
      do Result<&2, &1, String, Pt>:
        x : List<&2, String> <- Pj.read.repeated.string(v)
        return Pt{user_name, age, id, x, color, data, score, ok, nums}
    case 5:
      do Result<&2, &1, String, Pt>:
        x : U32 <- Pj.read.enum(~Color.from_name, v)
        return Pt{user_name, age, id, tags, x, data, score, ok, nums}
    case 6:
      do Result<&2, &1, String, Pt>:
        x : List<&2, U32> <- Pj.read.bytes(v)
        return Pt{user_name, age, id, tags, color, x, score, ok, nums}
    case 7:
      do Result<&2, &1, String, Pt>:
        x : F32 <- Pj.read.float(v)
        return Pt{user_name, age, id, tags, color, data, x, ok, nums}
    case 8:
      do Result<&2, &1, String, Pt>:
        x : Bool <- Pj.read.bool(v)
        return Pt{user_name, age, id, tags, color, data, score, x, nums}
    case 9:
      do Result<&2, &1, String, Pt>:
        x : List<&2, Pb.Word64> <- Pj.read.repeated.int64(v)
        return Pt{user_name, age, id, tags, color, data, score, ok, x}
    case _:
      Done{Pt{user_name, age, id, tags, color, data, score, ok, nums}}

def Pt.json_fold(kvs: List<&1, String & Json.Val>, m: Pt) -> Result<&2, &1, String, Pt>:
  match kvs:
    case Nil{}:
      Done{m}
    case Con{(k, v), t}:
      do Result<&2, &1, String, Pt>:
        m2 : Pt <- Pt.json_set(m, Pj.dispatch(k, Pt.json_keys()), v)
        Pt.json_fold(t, m2)

def Pt.from_json(v: Json.Val) -> Result<&2, &1, String, Pt>:
  do Result<&2, &1, String, Pt>:
    kvs : List<&1, String & Json.Val> <- Pj.fields(v)
    Pt.json_fold(kvs, Pt.default())

def Pt.show(r: Result<&2, &1, String, Pt>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{m}:
      text(Pt.to_json(m))

def full() -> Pt:
  Pt{"Ann", 4294967291, Pb.Word64{4294967295, 4294967295}, ["x", "y"], 1, [104, 105], 1.5, True{}, [Pb.Word64{0, 7}, Pb.Word64{2147483648, 0}]}

# ---- map<int32, string> entries
type Ent is Data:
  Ent{key: U32, value: String}

def ents(es: List<&2, Ent>) -> String:
  match es:
    case Nil{}:
      ""
    case Con{Ent{k, v}, t}:
      String.concat([U32.show(k), "=", v, ";", ents(t)])

def r_ents(r: Result<&2, &1, String, List<&2, Ent>>) -> String:
  match r:
    case Fail{e}:
      "fail"
    case Done{es}:
      ents(es)

def rd_map(v: Json.Val) -> Result<&2, &1, String, List<&2, Ent>>:
  Pj.read.map(~U32, ~String, ~Ent, ~Pj.read.key.int32, ~Pj.read.string, ~(+k => +v => Ent{k, v}), v)

def kvs_of.go(r: Result<&2, &1, String, List<&1, String & Json.Val>>) -> List<&1, String & Json.Val>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{kvs}:
      kvs

def kvs_of(v: Json.Val) -> List<&1, String & Json.Val>:
  kvs_of.go(Pj.fields(v))

def take_name(r: Json.Val & List<&1, String & Json.Val>) -> String:
  (v, rest) = r
  r_str(Pj.read.string(v))

def results() -> List<&2, String>:
  [
    # --- writers
    check("empty message is {}", String.eq(Pt.show(Done{Pt.default()}), "{}")),
    check("full message", String.eq(Pt.show(Done{full()}), "{\"userName\":\"Ann\",\"age\":-5,\"id\":\"-1\",\"tags\":[\"x\",\"y\"],\"color\":\"GREEN\",\"data\":\"aGk=\",\"score\":1.5,\"ok\":true,\"nums\":[\"7\",\"-9223372036854775808\"]}")),
    check("field order follows put order", String.eq(text(Pj.obj(Pj.put.int32("b", 2, Pj.put.int32("a", 1, Nil{})))), "{\"a\":1,\"b\":2}")),
    check("int64 is a quoted decimal", String.eq(text(Pj.obj(Pj.put.int64("n", Pb.Word64{0, 5}, Nil{}))), "{\"n\":\"5\"}")),
    check("uint64 max quoted", String.eq(text(Pj.obj(Pj.put.uint64("n", Pb.Word64{4294967295, 4294967295}, Nil{}))), "{\"n\":\"18446744073709551615\"}")),
    check("int64 min quoted", String.eq(text(Pj.obj(Pj.put.int64("n", Pb.Word64{2147483648, 0}, Nil{}))), "{\"n\":\"-9223372036854775808\"}")),
    check("uint32 is a number", String.eq(text(Pj.obj(Pj.put.uint32("n", 4294967295, Nil{}))), "{\"n\":4294967295}")),
    check("int32 negative", String.eq(text(Pj.obj(Pj.put.int32("n", 4294967295, Nil{}))), "{\"n\":-1}")),
    check("int32 min", String.eq(text(Pj.obj(Pj.put.int32("n", 2147483648, Nil{}))), "{\"n\":-2147483648}")),
    check("defaults skipped", String.eq(text(Pj.obj(Pj.put.bool("a", False{}, Pj.put.string("b", "", Pj.put.int64("c", Pb.Word64{0, 0}, Pj.put.bytes("d", [], Pj.put.float("e", 0.0, Nil{}))))))), "{}")),
    check("always keeps defaults", String.eq(text(Pj.obj(Pj.put.int32.always("a", 0, Pj.put.string.always("b", "", Pj.put.bool.always("c", False{}, Nil{}))))), "{\"c\":false,\"b\":\"\",\"a\":0}")),
    check("empty repeated skipped", String.eq(text(Pj.obj(Pj.put.repeated.int32("a", [], Nil{}))), "{}")),
    check("repeated int32", String.eq(text(Pj.obj(Pj.put.repeated.int32("a", [1, 4294967295], Nil{}))), "{\"a\":[1,-1]}")),
    check("bytes base64 padded", String.eq(text(Pj.obj(Pj.put.bytes("d", [102, 111], Nil{}))), "{\"d\":\"Zm8=\"}")),
    check("bytes base64 all values", String.eq(text(Pj.obj(Pj.put.bytes("d", [251, 255, 191], Nil{}))), "{\"d\":\"+/+/\"}")),
    check("enum name", String.eq(text(Pj.obj(Pj.put.enum(~Color.name, "c", 2, Nil{}))), "{\"c\":\"BLUE\"}")),
    check("enum default skipped", String.eq(text(Pj.obj(Pj.put.enum(~Color.name, "c", 0, Nil{}))), "{}")),
    check("enum default always", String.eq(text(Pj.obj(Pj.put.enum.always(~Color.name, "c", 0, Nil{}))), "{\"c\":\"RED\"}")),
    check("enum unknown prints number", String.eq(text(Pj.obj(Pj.put.enum(~Color.name, "c", 9, Nil{}))), "{\"c\":9}")),
    check("repeated enum", String.eq(text(Pj.obj(Pj.put.repeated.enum(~Color.name, "c", [1, 2, 7], Nil{}))), "{\"c\":[\"GREEN\",\"BLUE\",7]}")),
    check("nested message", String.eq(text(Pj.obj(Pj.put.message("m", Pt.to_json(Pt.default()), Nil{}))), "{\"m\":{}}")),
    check("repeated message", String.eq(text(Pj.obj(Pj.put.repeated.message("m", [Pt.to_json(Pt.default()), Pt.to_json(Pt.default())], Nil{}))), "{\"m\":[{},{}]}")),
    check("map entries", String.eq(text(Pj.obj(Pj.put.map("m", [Pj.entry(Pj.key.int32(4294967295), Pj.val.string("a")), Pj.entry(Pj.key.bool(True{}), Pj.val.int64(Pb.Word64{0, 1}))], Nil{}))), "{\"m\":{\"-1\":\"a\",\"true\":\"1\"}}")),
    check("string escapes and unicode", String.eq(text(Pj.obj(Pj.put.string("s", "é\n\"", Nil{}))), "{\"s\":\"é\\n\\\"\"}")),
    check("float 1.5", String.eq(text(Pj.val.float(1.5)), "1.5")),
    check("float NaN is a string", String.eq(text(Pj.val.float(F32.div(0.0, 0.0))), "\"NaN\"")),
    check("float +inf is a string", String.eq(text(Pj.val.float(F32.div(1.0, 0.0))), "\"Infinity\"")),
    check("float -inf is a string", String.eq(text(Pj.val.float(F32.div(F32.neg(1.0), 0.0))), "\"-Infinity\"")),
    check("float negative", String.eq(text(Pj.val.float(F32.neg(2.5))), "-2.5")),
    check("float 0.1 shortest", String.eq(text(Pj.val.double(0.1)), "0.1")),
    check("float -0.0 not default", String.eq(text(Pj.obj(Pj.put.float("f", F32.neg(0.0), Nil{}))), "{\"f\":-0}")),
    # --- readers
    check("round trip full", String.eq(Pt.show(Pt.from_json(Pt.to_json(full()))), Pt.show(Done{full()}))),
    check("round trip text", String.eq(Pt.show(Pt.from_json(pv(text(Pt.to_json(full()))))), Pt.show(Done{full()}))),
    check("proto name accepted", String.eq(Pt.show(Pt.from_json(pv("{\"user_name\":\"Bo\"}"))), "{\"userName\":\"Bo\"}")),
    check("json name accepted", String.eq(Pt.show(Pt.from_json(pv("{\"userName\":\"Bo\"}"))), "{\"userName\":\"Bo\"}")),
    check("unknown field ignored", String.eq(Pt.show(Pt.from_json(pv("{\"zzz\":[1,{}],\"age\":3}"))), "{\"age\":3}")),
    check("null is default", String.eq(Pt.show(Pt.from_json(pv("{\"userName\":null,\"age\":null,\"id\":null,\"tags\":null,\"color\":null,\"data\":null,\"score\":null,\"ok\":null,\"nums\":null}"))), "{}")),
    check("int64 from string", String.eq(Pt.show(Pt.from_json(pv("{\"id\":\"-9223372036854775808\"}"))), "{\"id\":\"-9223372036854775808\"}")),
    check("int64 from number", String.eq(Pt.show(Pt.from_json(pv("{\"id\":123}"))), "{\"id\":\"123\"}")),
    check("int32 from string", String.eq(Pt.show(Pt.from_json(pv("{\"age\":\"-7\"}"))), "{\"age\":-7}")),
    check("int32 out of range fails", String.eq(Pt.show(Pt.from_json(pv("{\"age\":2147483648}"))), "fail")),
    check("int32 min ok", String.eq(Pt.show(Pt.from_json(pv("{\"age\":-2147483648}"))), "{\"age\":-2147483648}")),
    check("int32 junk fails", String.eq(Pt.show(Pt.from_json(pv("{\"age\":\"x\"}"))), "fail")),
    check("int32 from bool fails", String.eq(Pt.show(Pt.from_json(pv("{\"age\":true}"))), "fail")),
    check("enum by name", String.eq(Pt.show(Pt.from_json(pv("{\"color\":\"BLUE\"}"))), "{\"color\":\"BLUE\"}")),
    check("enum by number", String.eq(Pt.show(Pt.from_json(pv("{\"color\":1}"))), "{\"color\":\"GREEN\"}")),
    check("enum unknown number kept", String.eq(Pt.show(Pt.from_json(pv("{\"color\":9}"))), "{\"color\":9}")),
    check("enum unknown name fails", String.eq(Pt.show(Pt.from_json(pv("{\"color\":\"PURPLE\"}"))), "fail")),
    check("bytes std padded", String.eq(r_list(Pj.read.bytes(pv("\"aGk=\""))), "104,105,")),
    check("bytes unpadded", String.eq(r_list(Pj.read.bytes(pv("\"aGk\""))), "104,105,")),
    check("bytes url-safe", String.eq(r_list(Pj.read.bytes(pv("\"-_-_\""))), "251,255,191,")),
    check("bytes invalid fails", String.eq(r_list(Pj.read.bytes(pv("\"a$\""))), "fail")),
    check("bytes null empty", String.eq(r_list(Pj.read.bytes(pv("null"))), "")),
    check("repeated null empty", String.eq(r_list(Pj.read.repeated.int32(pv("null"))), "")),
    check("repeated int32", String.eq(r_list(Pj.read.repeated.int32(pv("[1,\"2\",-1]"))), "1,2,4294967295,")),
    check("repeated not an array fails", String.eq(r_list(Pj.read.repeated.int32(pv("5"))), "fail")),
    check("repeated bad element fails", String.eq(r_list(Pj.read.repeated.int32(pv("[1,true]"))), "fail")),
    check("repeated string", String.eq(r_strs(Pj.read.repeated.string(pv("[\"a\",\"b\"]"))), "a,b,")),
    check("repeated enum", String.eq(r_list(Pj.read.repeated.enum(~Color.from_name, pv("[\"GREEN\",2]"))), "1,2,")),
    check("uint32 from -1 fails", String.eq(r_u32(Pj.read.uint32(pv("-1"))), "fail")),
    check("uint32 max", String.eq(r_u32(Pj.read.uint32(pv("4294967295"))), "4294967295")),
    check("uint32 overflow fails", String.eq(r_u32(Pj.read.uint32(pv("4294967296"))), "fail")),
    check("uint64 max from string", String.eq(r_i64(Pj.read.uint64(pv("\"18446744073709551615\""))), "-1")),
    check("uint64 overflow fails", String.eq(r_i64(Pj.read.uint64(pv("\"18446744073709551616\""))), "fail")),
    check("bool", String.eq(r_bool(Pj.read.bool(pv("true"))), "True")),
    check("bool null", String.eq(r_bool(Pj.read.bool(pv("null"))), "False")),
    check("bool from string fails", String.eq(r_bool(Pj.read.bool(pv("\"true\""))), "fail")),
    check("string from number fails", String.eq(r_str(Pj.read.string(pv("1"))), "fail")),
    check("string unicode escape", String.eq(r_str(Pj.read.string(pv("\"\\u00e9\\n\""))), "é\n")),
    check("float from number", String.eq(r_f(Pj.read.float(pv("1.5"))), "1.5")),
    check("float from string", String.eq(r_f(Pj.read.float(pv("\"-2.5\""))), "-2.5")),
    check("float exponent", String.eq(r_f(Pj.read.double(pv("1e3"))), "1000")),
    check("float NaN", String.eq(r_f(Pj.read.float(pv("\"NaN\""))), "nan")),
    check("float Infinity", String.eq(r_f(Pj.read.float(pv("\"Infinity\""))), "inf")),
    check("float -Infinity", String.eq(r_f(Pj.read.float(pv("\"-Infinity\""))), "-inf")),
    check("float junk fails", String.eq(r_f(Pj.read.float(pv("\"abc\""))), "fail")),
    check("float null", String.eq(r_f(Pj.read.float(pv("null"))), "0")),
    check("opt null is None", String.eq(r_opt(Pj.read.opt(~U32, ~Pj.read.int32, pv("null"))), "none")),
    check("opt present is Some", String.eq(r_opt(Pj.read.opt(~U32, ~Pj.read.int32, pv("0"))), "0")),
    check("opt bad fails", String.eq(r_opt(Pj.read.opt(~U32, ~Pj.read.int32, pv("true"))), "fail")),
    check("fields rejects non-object", String.eq(Pt.show(Pt.from_json(pv("[1]"))), "fail")),
    check("fields rejects null", String.eq(Pt.show(Pt.from_json(pv("null"))), "fail")),
    check("map read", String.eq(r_ents(rd_map(pv("{\"1\":\"a\",\"-2\":\"b\"}"))), "1=a;4294967294=b;")),
    check("map null empty", String.eq(r_ents(rd_map(pv("null"))), "")),
    check("map bad key fails", String.eq(r_ents(rd_map(pv("{\"x\":\"a\"}"))), "fail")),
    check("map bad value fails", String.eq(r_ents(rd_map(pv("{\"1\":5}"))), "fail")),
    check("take by json name", String.eq(take_name(Pj.take(kvs_of(pv("{\"a\":\"x\",\"userName\":\"u\"}")), "userName", "user_name")), "u")),
    check("take by proto name", String.eq(take_name(Pj.take(kvs_of(pv("{\"user_name\":\"u\"}")), "userName", "user_name")), "u")),
    check("take absent is null -> default", String.eq(take_name(Pj.take(kvs_of(pv("{\"a\":1}")), "userName", "user_name")), "")),
    check("parse invalid is null", String.eq(text(pv("{")), "null")),
    check("parse/encode round trip", String.eq(text(pv("{\"a\":[1,2,{\"b\":null}],\"c\":\"d\"}")), "{\"a\":[1,2,{\"b\":null}],\"c\":\"d\"}"))
  ]

def main() -> IO(Unit):
  List.for_each(~&2, ~String, ~IO.print, results())
