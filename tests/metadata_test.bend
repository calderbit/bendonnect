import Base
import ../src/metadata.bend as Md

def check(name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      String.append("PASS ", name)
    case False{}:
      String.append("FAIL ", name)

# value of key joined with ",", or "<none>"
def look.fin(r: Map<&2, List<&2, String>> & Maybe<&2, List<&2, String>>) -> String:
  (m, v) = r
  match v:
    case None{}:
      "<none>"
    case Some{xs}:
      String.join(xs, ",")

def look(m: Map<&2, List<&2, String>>, +k: String) -> String:
  look.fin(Map.pop(&2, List<&2, String>, m, k))

def size.fin(r: Map<&2, List<&2, String>> & Nat) -> Nat:
  (m, n) = r
  n

def sample() -> Map<&2, List<&2, String>>:
  Map.set(&2, List<&2, String>, Map.set(&2, List<&2, String>, Map.new(&2, List<&2, String>), "x-a", ["1", "2"]), "grpc-status-details-bin", ["abc"])

def mixed() -> Map<&2, List<&2, String>>:
  Map.set(&2, List<&2, String>, Map.set(&2, List<&2, String>, Map.new(&2, List<&2, String>), "trailer-x-t", ["t1"]), "content-type", ["a/b"])

def tr() -> Map<&2, List<&2, String>>:
  Md.trailers_to_headers(sample())

def sp.h(r: Map<&2, List<&2, String>> & Map<&2, List<&2, String>>, +k: String) -> String:
  (h, t) = r
  look(h, k)

def sp.t(r: Map<&2, List<&2, String>> & Map<&2, List<&2, String>>, +k: String) -> String:
  (h, t) = r
  look(t, k)

def main() -> List<&2, String>:
  [
    check("prefix adds trailer-", String.eq(look(tr(), "trailer-x-a"), "1,2")),
    check("prefix removes bare key", String.eq(look(tr(), "x-a"), "<none>")),
    check("prefix bin key", String.eq(look(tr(), "trailer-grpc-status-details-bin"), "abc")),
    check("split header", String.eq(sp.h(Md.split_trailers(mixed()), "content-type"), "a/b")),
    check("split header excludes trailer", String.eq(sp.h(Md.split_trailers(mixed()), "trailer-x-t"), "<none>")),
    check("split trailer stripped", String.eq(sp.t(Md.split_trailers(mixed()), "x-t"), "t1")),
    check("split trailer excludes header", String.eq(sp.t(Md.split_trailers(mixed()), "content-type"), "<none>")),
    check("roundtrip x-a", String.eq(sp.t(Md.split_trailers(tr()), "x-a"), "1,2")),
    check("roundtrip no headers", String.eq(sp.h(Md.split_trailers(tr()), "x-a"), "<none>")),
    check("reserved connect-", Md.is_reserved("connect-timeout-ms")),
    check("not reserved", Bool.not(Md.is_reserved("x-connect-a"))),
    check("not reserved connect", Bool.not(Md.is_reserved("connect"))),
    check("binary", Md.is_binary("foo-bin")),
    check("not binary", Bool.not(Md.is_binary("foo-bina"))),
    check("not binary short", Bool.not(Md.is_binary("bin"))),
    check("valid x-a_b.c9", Md.valid_key("x-a_b.c9")),
    check("invalid empty", Bool.not(Md.valid_key(""))),
    check("invalid upper", Bool.not(Md.valid_key("X-a"))),
    check("invalid space", Bool.not(Md.valid_key("a b"))),
    check("invalid colon", Bool.not(Md.valid_key("a:b"))),
    check("invalid slash", Bool.not(Md.valid_key("a/b")))
  ]
