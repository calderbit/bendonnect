# Run: bend tests/protocol_test.bend   (every entry must be True)
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ../src/code.bend as Code
import ../src/protocol.bend as P

def hnew() -> Map<&2, List<&2, String>>:
  Map.new(&2, List<&2, String>)

def hset(m: Map<&2, List<&2, String>>, k: String, v: String) -> Map<&2, List<&2, String>>:
  Map.set(&2, List<&2, String>, m, k, [v])

def h1(k: String, v: String) -> Map<&2, List<&2, String>>:
  hset(hnew(), k, v)

def h2(k: String, v: String, k2: String, v2: String) -> Map<&2, List<&2, String>>:
  hset(hset(hnew(), k, v), k2, v2)

def ct(v: String) -> Map<&2, List<&2, String>>:
  h2("content-type", v, "connect-protocol-version", "1")

def kind_s(k: P.CallKind) -> String:
  match k:
    case P.Unary{}:
      "unary"
    case P.UnaryGet{}:
      "get"
    case P.Stream{}:
      "stream"

def codec_s(c: P.Codec) -> String:
  match c:
    case P.Json{}:
      "json"
    case P.Proto{}:
      "proto"
    case P.Custom{n}:
      "custom:" ++ n

def timeout_s(t: Maybe<&2, U32>) -> String:
  match t:
    case None{}:
      "-"
    case Some{n}:
      U32.show(n)

def show_spec(s: P.Spec) -> String:
  match s:
    case P.Spec{p, k, c, t, e, a, m}:
      "ok:" ++ p ++ "|" ++ kind_s(k) ++ "|" ++ codec_s(c) ++ "|" ++ timeout_s(t) ++ "|" ++ e ++ "|" ++ String.join(a, ",") ++ "|" ++ Bytes.to_hex(m)

def show_rej(r: P.Reject) -> String:
  match r:
    case P.Status{s, m}:
      "status:" ++ U32.show(s)
    case P.Connect{c, m}:
      "connect:" ++ Code.to_string(c) ++ ":" ++ m

def show(r: Result<&2, &1, P.Reject, P.Spec>) -> String:
  match r:
    case Fail{e}:
      show_rej(e)
    case Done{s}:
      show_spec(s)

def eq(a: String, b: String) -> Bool:
  String.eq(a, b)

def post(+path: String, h: Map<&2, List<&2, String>>) -> String:
  show(P.classify("POST", path, "", h, ""))

def get(+q: String) -> String:
  show(P.classify("GET", "/connectrpc.eliza.v1.ElizaService/Say", q, hnew(), ""))

def geth(+q: String, h: Map<&2, List<&2, String>>) -> String:
  show(P.classify("GET", "/connectrpc.eliza.v1.ElizaService/Say", q, h, ""))

def proc() -> String:
  "connectrpc.eliza.v1.ElizaService/Say"

def path() -> String:
  "/connectrpc.eliza.v1.ElizaService/Say"

def msg_hex() -> String:
  "7b226e616d65223a2022427566227d"

def json_q() -> String:
  "%7B%22name%22%3A%20%22Buf%22%7D"

def b64s.of(m: Maybe<&1, Bytes.Bytes>) -> String:
  match m:
    case None{}:
      "none"
    case Some{b}:
      Bytes.to_hex(b)

def b64s(+s: String) -> String:
  b64s.of(P.b64url_decode(s))

def main() -> List<&2, Bool>:
  [
    # ---- unary POST
    eq(post(path(), ct("application/json")), "ok:" ++ proc() ++ "|unary|json|-|identity|identity|"),
    eq(post(path(), ct("application/proto")), "ok:" ++ proc() ++ "|unary|proto|-|identity|identity|"),
    eq(post(path(), ct("application/x-foo")), "ok:" ++ proc() ++ "|unary|custom:x-foo|-|identity|identity|"),
    eq(post(path(), ct("Application/JSON; charset=utf-8")), "ok:" ++ proc() ++ "|unary|json|-|identity|identity|"),
    # connect-protocol-version is optional on POST
    eq(post(path(), h1("content-type", "application/json")), "ok:" ++ proc() ++ "|unary|json|-|identity|identity|"),
    eq(post(path(), h2("content-type", "application/json", "connect-protocol-version", "2")), "status:400"),
    # timeout
    eq(post(path(), hset(ct("application/json"), "connect-timeout-ms", "5000")), "ok:" ++ proc() ++ "|unary|json|5000|identity|identity|"),
    eq(post(path(), hset(ct("application/json"), "connect-timeout-ms", "9999999999")), "ok:" ++ proc() ++ "|unary|json|4294967295|identity|identity|"),
    eq(post(path(), hset(ct("application/json"), "connect-timeout-ms", "abc")), "connect:invalid_argument:invalid connect-timeout-ms \"abc\""),
    eq(post(path(), hset(ct("application/json"), "connect-timeout-ms", "12345678901")), "connect:invalid_argument:invalid connect-timeout-ms \"12345678901\""),
    eq(post(path(), hset(ct("application/json"), "connect-timeout-ms", "")), "connect:invalid_argument:invalid connect-timeout-ms \"\""),
    eq(post(path(), hset(ct("application/json"), "connect-timeout-ms", "-5")), "connect:invalid_argument:invalid connect-timeout-ms \"-5\""),
    # encodings
    eq(post(path(), hset(ct("application/json"), "content-encoding", "gzip")), "connect:unimplemented:unknown compression \"gzip\": supported encodings are identity"),
    eq(post(path(), hset(ct("application/json"), "content-encoding", "identity")), "ok:" ++ proc() ++ "|unary|json|-|identity|identity|"),
    eq(post(path(), hset(ct("application/json"), "content-encoding", "")), "ok:" ++ proc() ++ "|unary|json|-|identity|identity|"),
    eq(post(path(), hset(ct("application/json"), "accept-encoding", "gzip, br,identity")), "ok:" ++ proc() ++ "|unary|json|-|identity|gzip,br,identity|"),
    # a streaming-only header is ignored for unary and vice versa
    eq(post(path(), hset(ct("application/json"), "connect-content-encoding", "gzip")), "ok:" ++ proc() ++ "|unary|json|-|identity|identity|"),
    # ---- streaming POST
    eq(post(path(), ct("application/connect+json")), "ok:" ++ proc() ++ "|stream|json|-|identity|identity|"),
    eq(post(path(), ct("application/connect+proto")), "ok:" ++ proc() ++ "|stream|proto|-|identity|identity|"),
    eq(post(path(), ct("application/connect+x-bar")), "ok:" ++ proc() ++ "|stream|custom:x-bar|-|identity|identity|"),
    eq(post(path(), hset(ct("application/connect+json"), "connect-content-encoding", "gzip")), "connect:unimplemented:unknown compression \"gzip\": supported encodings are identity"),
    eq(post(path(), hset(ct("application/connect+json"), "content-encoding", "gzip")), "ok:" ++ proc() ++ "|stream|json|-|identity|identity|"),
    eq(post(path(), hset(ct("application/connect+json"), "connect-accept-encoding", "gzip,identity")), "ok:" ++ proc() ++ "|stream|json|-|identity|gzip,identity|"),
    eq(post(path(), hset(ct("application/connect+json"), "connect-timeout-ms", "250")), "ok:" ++ proc() ++ "|stream|json|250|identity|identity|"),
    # ---- content-type rejections
    eq(post(path(), h1("connect-protocol-version", "1")), "status:415"),
    eq(post(path(), ct("text/plain")), "status:415"),
    eq(post(path(), ct("")), "status:415"),
    eq(post(path(), ct("application/")), "status:415"),
    eq(post(path(), ct("application/connect+")), "status:415"),
    eq(post(path(), ct("json")), "status:415"),
    # ---- path
    eq(post("/svc", ct("application/json")), "status:404"),
    eq(post("", ct("application/json")), "status:404"),
    eq(post("/", ct("application/json")), "status:404"),
    eq(post("/a/b/c", ct("application/json")), "status:404"),
    eq(post("//Method", ct("application/json")), "status:404"),
    eq(post("/pkg.Svc/", ct("application/json")), "status:404"),
    eq(post("/pkg.Svc/M/", ct("application/json")), "status:404"),
    eq(post("pkg.Svc/M", ct("application/json")), "status:404"),
    eq(post("/pkg.Svc/M", ct("application/json")), "ok:pkg.Svc/M|unary|json|-|identity|identity|"),
    eq(show(P.classify("POST", "/api/pkg.Svc/M", "", ct("application/json"), "/api")), "ok:pkg.Svc/M|unary|json|-|identity|identity|"),
    eq(show(P.classify("POST", "/other/pkg.Svc/M", "", ct("application/json"), "/api")), "status:404"),
    eq(show(P.classify("POST", "/pkg.Svc/M", "", ct("application/json"), "/api")), "status:404"),
    eq(show(P.classify("POST", "/api/M", "", ct("application/json"), "/api")), "status:404"),
    eq(show(P.classify("GET", "/bad", "message=%7B%7D&encoding=json", hnew(), "")), "status:404"),
    # ---- methods
    eq(show(P.classify("PUT", path(), "", ct("application/json"), "")), "status:405"),
    eq(show(P.classify("DELETE", path(), "", ct("application/json"), "")), "status:405"),
    eq(show(P.classify("HEAD", path(), "", ct("application/json"), "")), "status:405"),
    eq(show(P.classify("OPTIONS", path(), "", ct("application/json"), "")), "status:405"),
    eq(show(P.classify("post", path(), "", ct("application/json"), "")), "status:405"),
    # ---- GET: spec example
    eq(get("message=" ++ json_q() ++ "&encoding=json&connect=v1"), "ok:" ++ proc() ++ "|get|json|-|identity|identity|" ++ msg_hex()),
    eq(get("encoding=json&foo=bar&message=" ++ json_q()), "ok:" ++ proc() ++ "|get|json|-|identity|identity|" ++ msg_hex()),
    eq(get("connect=v1&encoding=json&message=%7B%7D"), "ok:" ++ proc() ++ "|get|json|-|identity|identity|7b7d"),
    eq(get("message=&encoding=proto"), "ok:" ++ proc() ++ "|get|proto|-|identity|identity|"),
    eq(get("message=%7B%7D&encoding=x-foo"), "ok:" ++ proc() ++ "|get|custom:x-foo|-|identity|identity|7b7d"),
    # GET: base64
    eq(get("base64=1&connect=v1&encoding=proto&message=CgNCdWY"), "ok:" ++ proc() ++ "|get|proto|-|identity|identity|0a03427566"),
    eq(get("base64=1&encoding=proto&message=CgNCdWY%3D"), "ok:" ++ proc() ++ "|get|proto|-|identity|identity|0a03427566"),
    eq(get("base64=1&encoding=proto&message=CgNCdWY="), "ok:" ++ proc() ++ "|get|proto|-|identity|identity|0a03427566"),
    eq(get("message=-_8&encoding=proto&base64=1"), "ok:" ++ proc() ++ "|get|proto|-|identity|identity|fbff"),
    eq(get("message=&encoding=proto&base64=1"), "ok:" ++ proc() ++ "|get|proto|-|identity|identity|"),
    eq(get("message=a&encoding=proto&base64=1"), "status:400"),
    eq(get("message=a*bc&encoding=proto&base64=1"), "status:400"),
    # without base64=1 the message is taken literally
    eq(get("message=CgNCdWY&encoding=proto&base64=0"), "ok:" ++ proc() ++ "|get|proto|-|identity|identity|43674e43645759"),
    eq(get("message=%7B%7D&encoding=json&compression=identity"), "ok:" ++ proc() ++ "|get|json|-|identity|identity|7b7d"),
    eq(get("message=%7B%7D&encoding=json&compression=gzip"), "connect:unimplemented:unknown compression \"gzip\": supported encodings are identity"),
    eq(geth("message=%7B%7D&encoding=json", h2("connect-timeout-ms", "100", "accept-encoding", "gzip,identity")), "ok:" ++ proc() ++ "|get|json|100|identity|gzip,identity|7b7d"),
    eq(geth("message=%7B%7D&encoding=json", h1("connect-timeout-ms", "zz")), "connect:invalid_argument:invalid connect-timeout-ms \"zz\""),
    # GET rejections
    eq(get("encoding=json"), "status:400"),
    eq(get("message=%7B%7D"), "status:400"),
    eq(get(""), "status:400"),
    eq(get("message=%7B%7D&encoding="), "status:400"),
    eq(get("message=%7B%7D&encoding=json&connect=v2"), "status:400"),
    eq(get("message=%zz&encoding=json"), "status:400"),
    eq(geth("message=%7B%7D&encoding=json", h1("connect-protocol-version", "2")), "status:400"),
    # ---- helpers
    eq(timeout_s(P.parse_timeout("1")), "1"),
    eq(timeout_s(P.parse_timeout("0")), "0"),
    eq(timeout_s(P.parse_timeout("1234567890")), "1234567890"),
    eq(timeout_s(P.parse_timeout("4294967295")), "4294967295"),
    eq(timeout_s(P.parse_timeout("4294967296")), "4294967295"),
    eq(timeout_s(P.parse_timeout("9999999999")), "4294967295"),
    eq(timeout_s(P.parse_timeout("")), "-"),
    eq(timeout_s(P.parse_timeout("12345678901")), "-"),
    eq(timeout_s(P.parse_timeout("1.5")), "-"),
    eq(timeout_s(P.parse_timeout(" 5")), "-"),
    eq(P.unary_content_type(P.Json{}), "application/json"),
    eq(P.unary_content_type(P.Proto{}), "application/proto"),
    eq(P.unary_content_type(P.Custom{"x"}), "application/x"),
    eq(P.stream_content_type(P.Json{}), "application/connect+json"),
    eq(P.stream_content_type(P.Proto{}), "application/connect+proto"),
    eq(String.join(P.supported_encodings(), ","), "identity"),
    eq(b64s("Zm9vYmFy"), "666f6f626172"),
    eq(b64s("Zm9vYg"), "666f6f62"),
    eq(b64s("Zm9vYg=="), "666f6f62"),
    eq(b64s("Zm9v"), "666f6f"),
    eq(b64s("/w=="), "ff"),
    eq(b64s("_w"), "ff"),
    eq(b64s(""), ""),
    eq(b64s("Z"), "none"),
    eq(b64s("Zm9vY"), "none")
  ]
