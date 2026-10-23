# NOTE: `Kind` is a reserved word in Bend, so the contract's `Kind` type is named `CallKind`.
# Connect request classification (pure): turns an HTTP request line + headers into a Spec
# or a Reject. https://connectrpc.com/docs/protocol/
#
# Choices (where the spec leaves room):
# - `query` is the RAW query string without the leading '?' (e.g. "message=%7B%7D&encoding=json").
#   Keys and values are matched/decoded here; unknown params are ignored.
# - `prefix` is "" or a path such as "/api" (no trailing slash). Path = prefix "/" Service "/" Method.
# - Check order: method (405) -> path (404) -> content-type / GET params (415 / 400)
#   -> connect-protocol-version (400) -> timeout (InvalidArgument) -> encoding (Unimplemented).
# - GET with missing/empty `encoding` or `message` is Status 400 (not 415).
# - Unsupported codecs are NOT rejected here: unknown codecs become Custom{name} (415 is the
#   caller's call once it knows its codec registry). An empty codec name is Status 415.
# - GET also validates the connect-protocol-version header, if sent, like POST.
# - `encoding`: lowercased/trimmed; empty or absent is "identity".
# - `accept`: header present -> its comma list (trimmed, lowercased, ";q=" params and empties dropped);
#   absent -> [encoding] (spec: client accepts the encoding it used; identity is implied last).
# - Methods are matched case-sensitively ("POST", "GET"); anything else is Status 405.
import Base
import ./code.bend as Code
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-url@0.4.1.0/url.bend as Url

type Codec is Data:
  Json{}
  Proto{}
  Custom{name: String}

type CallKind is Data:
  Unary{}
  UnaryGet{}
  Stream{}

type Spec is Type:
  Spec{procedure: String, kind: CallKind, codec: Codec, timeout_ms: Maybe<&2, U32>,
    encoding: String, accept: List<&2, String>, message: Bytes.Bytes}

type Reject is Data:
  Status{status: U32, message: String}
  Connect{code: Code.Code, message: String}

# A parsed Content-Type: stream = application/connect+<codec>.
type Ct is Data:
  Ct{stream: Bool, codec: Codec}

def supported_encodings() -> List<&2, String>:
  ["identity"]

# ---------------------------------------------------------------- content types

def codec_name(c: Codec) -> String:
  match c:
    case Json{}:
      "json"
    case Proto{}:
      "proto"
    case Custom{n}:
      n

def content_type(+stream: Bool, c: Codec) -> String:
  match stream:
    case True{}:
      "application/connect+" ++ codec_name(c)
    case False{}:
      "application/" ++ codec_name(c)

def unary_content_type(c: Codec) -> String:
  content_type(False{}, c)

def stream_content_type(c: Codec) -> String:
  content_type(True{}, c)

# json / proto / other (non-empty) -> Custom
def codec_of(+name: String) -> Maybe<&2, Codec>:
  Bool.pick(Maybe<&2, Codec>, String.eq(name, "json"), Some{Json{}},
    Bool.pick(Maybe<&2, Codec>, String.eq(name, "proto"), Some{Proto{}},
      Bool.pick(Maybe<&2, Codec>, String.is_empty(name), None{}, Some{Custom{name}})))

def media.of(r: String & String) -> String:
  (a, b) = r
  a

# text before the first ';'
def media(s: String) -> String:
  media.of(Url.take_to(s, 59))

def ct_make(stream: Bool, mc: Maybe<&2, Codec>) -> Maybe<&2, Ct>:
  match mc:
    case None{}:
      None{}
    case Some{c}:
      Some{Ct{stream, c}}

def ct_split(stream: Bool, app: Bool, +m: String) -> Maybe<&2, Ct>:
  match stream:
    case True{}:
      ct_make(True{}, codec_of(String.drop(m, 20n)))
    case False{}:
      match app:
        case True{}:
          ct_make(False{}, codec_of(String.drop(m, 12n)))
        case False{}:
          None{}

# "application/json; charset=utf-8" -> Ct{False, Json}; case-insensitive; None if not application/*.
def parse_content_type(+ct: String) -> Maybe<&2, Ct>:
  +m = String.to_lower(String.trim(media(ct)))
  ct_split(String.starts_with(m, "application/connect+"), String.starts_with(m, "application/"), m)

def ct_stream(c: Ct) -> Bool:
  match c:
    case Ct{s, k}:
      s

def ct_codec(c: Ct) -> Codec:
  match c:
    case Ct{s, k}:
      k

def ct_kind(c: Ct) -> CallKind:
  match c:
    case Ct{s, k}:
      match s:
        case True{}:
          Stream{}
        case False{}:
          Unary{}

# ---------------------------------------------------------------- headers

def hdr.of(r: Map<&2, List<&2, String>> & List<&2, String>) -> Maybe<&2, String>:
  (m, v) = r
  match v:
    case Nil{}:
      None{}
    case Con{x, rest}:
      Some{x}

# First value of a (lowercase) header.
def hdr(+h: Map<&2, List<&2, String>>, +k: String) -> Maybe<&2, String>:
  hdr.of(Map.get(List<&2, String>, Nil{}, h, k))

def hdr_all.of(r: Map<&2, List<&2, String>> & List<&2, String>) -> Maybe<&2, String>:
  (m, v) = r
  match v:
    case Nil{}:
      None{}
    case Con{x, rest}:
      Some{String.join(Con{x, rest}, ",")}

# All values of a header joined with ",".
def hdr_all(+h: Map<&2, List<&2, String>>, +k: String) -> Maybe<&2, String>:
  hdr_all.of(Map.get(List<&2, String>, Nil{}, h, k))

def bad_media() -> Result<&2, &1, Reject, Ct>:
  Fail{Status{415, "unsupported content-type: want application/<codec> or application/connect+<codec>"}}

def content_type_of.fin(m: Maybe<&2, Ct>) -> Result<&2, &1, Reject, Ct>:
  match m:
    case None{}:
      bad_media()
    case Some{c}:
      Done{c}

def content_type_of.of(m: Maybe<&2, String>) -> Result<&2, &1, Reject, Ct>:
  match m:
    case None{}:
      bad_media()
    case Some{s}:
      content_type_of.fin(parse_content_type(s))

def content_type_of(+h: Map<&2, List<&2, String>>) -> Result<&2, &1, Reject, Ct>:
  content_type_of.of(hdr(h, "content-type"))

def version_ok(ok: Bool) -> Result<&2, &1, Reject, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{Status{400, "unsupported connect-protocol-version: want \"1\""}}

def check_version.of(v: Maybe<&2, String>) -> Result<&2, &1, Reject, Unit>:
  match v:
    case None{}:
      Done{Unit{}}
    case Some{s}:
      version_ok(String.eq(s, "1"))

# connect-protocol-version, if present, must be "1".
def check_version(+h: Map<&2, List<&2, String>>) -> Result<&2, &1, Reject, Unit>:
  check_version.of(hdr(h, "connect-protocol-version"))

# ---------------------------------------------------------------- timeout

def digit(+c: U32) -> Bool:
  Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))

# acc*10 + d, clamped to U32 max.
def sat(+acc: U32, +d: U32) -> U32:
  Bool.pick(U32, U32.is_gt(acc, 429496729), 4294967295,
    Bool.pick(U32, Bool.and(U32.is_eq(acc, 429496729), U32.is_gt(d, 5)), 4294967295,
      (acc * 10 + d : U32)))

def pt.pick(ok: Bool, rest: Unit -> Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      rest(Unit{})
    case False{}:
      None{}

def pt.go(s: String, +n: U32, +acc: U32) -> Maybe<&2, U32>:
  match s:
    case SNil{}:
      Some{acc}
    case SCon{Chr{+c}, t}:
      pt.pick(Bool.and(digit(c), U32.is_lt(n, 10)), u => pt.go(t, (n + 1 : U32), sat(acc, (c - 48 : U32))))

def pt.start(+s: String, empty: Bool) -> Maybe<&2, U32>:
  match empty:
    case True{}:
      None{}
    case False{}:
      pt.go(s, 0, 0)

# connect-timeout-ms value: 1..10 ASCII digits, clamped to U32 max.
def parse_timeout(+s: String) -> Maybe<&2, U32>:
  pt.start(s, String.is_empty(s))

def timeout.chk(m: Maybe<&2, U32>, +s: String) -> Result<&2, &1, Reject, Maybe<&2, U32>>:
  match m:
    case None{}:
      Fail{Connect{Code.InvalidArgument{}, "invalid connect-timeout-ms \"" ++ s ++ "\""}}
    case Some{t}:
      Done{Some{t}}

def timeout.of(v: Maybe<&2, String>) -> Result<&2, &1, Reject, Maybe<&2, U32>>:
  match v:
    case None{}:
      Done{None{}}
    case Some{+s}:
      timeout.chk(parse_timeout(s), s)

def timeout_of(+h: Map<&2, List<&2, String>>) -> Result<&2, &1, Reject, Maybe<&2, U32>>:
  timeout.of(hdr(h, "connect-timeout-ms"))

# ---------------------------------------------------------------- encodings

def norm.pick(empty: Bool, +e: String) -> String:
  match empty:
    case True{}:
      "identity"
    case False{}:
      e

def norm_enc(+s: String) -> String:
  +e = String.to_lower(String.trim(s))
  norm.pick(String.is_empty(e), e)

def enc.fin(ok: Bool, +e: String) -> Result<&2, &1, Reject, String>:
  match ok:
    case True{}:
      Done{e}
    case False{}:
      Fail{Connect{Code.Unimplemented{}, "unknown compression \"" ++ e ++ "\": supported encodings are " ++ String.join(supported_encodings(), ", ")}}

# Normalizes an encoding name; Unimplemented unless it is identity.
def check_enc(+raw: String) -> Result<&2, &1, Reject, String>:
  +e = norm_enc(raw)
  enc.fin(String.eq(e, "identity"), e)

def get_enc.of(v: Maybe<&2, String>) -> Result<&2, &1, Reject, String>:
  match v:
    case None{}:
      Done{"identity"}
    case Some{s}:
      check_enc(s)

def get_enc(+h: Map<&2, List<&2, String>>, +k: String) -> Result<&2, &1, Reject, String>:
  get_enc.of(hdr(h, k))

def acc.item(+s: String) -> String:
  +e = String.to_lower(String.trim(media(s)))
  e

def acc.cons(empty: Bool, x: String, r: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      r
    case False{}:
      x <> r

def acc.item2(+x: String, r: List<&2, String>) -> List<&2, String>:
  acc.cons(String.is_empty(x), x, r)

def acc.go(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      acc.item2(acc.item(h), acc.go(t))

def accept_list(+s: String) -> List<&2, String>:
  acc.go(String.split(s, ','))

def accept.of(v: Maybe<&2, String>, +enc: String) -> List<&2, String>:
  match v:
    case None{}:
      [enc]
    case Some{s}:
      accept_list(s)

def accept_of(+h: Map<&2, List<&2, String>>, +k: String, +enc: String) -> List<&2, String>:
  accept.of(hdr_all(h, k), enc)

# ---------------------------------------------------------------- path

def bad_path() -> Result<&2, &1, Reject, String>:
  Fail{Status{404, "not found: want <prefix>/<package.Service>/<Method>"}}

def proc.fin(ok: Bool, +p: String) -> Result<&2, &1, Reject, String>:
  match ok:
    case True{}:
      Done{p}
    case False{}:
      bad_path()

def proc.parts(xs: List<&2, String>, +p: String) -> Result<&2, &1, Reject, String>:
  match xs:
    case Con{+s, Con{+m, Nil{}}}:
      proc.fin(Bool.and(Bool.not(String.is_empty(s)), Bool.not(String.is_empty(m))), p)
    case _:
      bad_path()

def proc.split(+p: String) -> Result<&2, &1, Reject, String>:
  proc.parts(String.split(p, '/'), p)

def proc.slash(ok: Bool, +rest: String) -> Result<&2, &1, Reject, String>:
  match ok:
    case True{}:
      proc.split(String.drop(rest, 1n))
    case False{}:
      bad_path()

def proc.pre(ok: Bool, +path: String, +prefix: String) -> Result<&2, &1, Reject, String>:
  match ok:
    case True{}:
      +rest = String.drop(path, String.length(prefix))
      proc.slash(String.starts_with(rest, "/"), rest)
    case False{}:
      bad_path()

# "<prefix>/pkg.Service/Method" -> "pkg.Service/Method"; else Status 404.
def parse_proc(+path: String, +prefix: String) -> Result<&2, &1, Reject, String>:
  proc.pre(String.starts_with(path, prefix), path, prefix)

# ---------------------------------------------------------------- POST

def post_enc_key(stream: Bool) -> String:
  match stream:
    case True{}:
      "connect-content-encoding"
    case False{}:
      "content-encoding"

def post_acc_key(stream: Bool) -> String:
  match stream:
    case True{}:
      "connect-accept-encoding"
    case False{}:
      "accept-encoding"

def post_req(+path: String, +headers: Map<&2, List<&2, String>>, +prefix: String) -> Result<&2, &1, Reject, Spec>:
  do Result<&2, &1, Reject, Spec>:
    proc : String <- parse_proc(path, prefix)
    +ct : Ct <- content_type_of(headers)
    ok : Unit <- check_version(headers)
    t : Maybe<&2, U32> <- timeout_of(headers)
    +enc : String <- get_enc(headers, post_enc_key(ct_stream(ct)))
    return Spec{proc, ct_kind(ct), ct_codec(ct), t, enc, accept_of(headers, post_acc_key(ct_stream(ct)), enc), Bytes.new(0)}

# ---------------------------------------------------------------- GET

def qfind.pick(hit: Bool, v: String, rest: Unit -> Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest(Unit{})

def qfind.kv(r: String & String, +name: String, rest: Unit -> Maybe<&2, String>) -> Maybe<&2, String>:
  (k, v) = r
  qfind.pick(String.eq(k, name), v, rest)

# First raw value of query param `name` in a list of "k=v" items.
def qfind(xs: List<&2, String>, +name: String) -> Maybe<&2, String>:
  match xs:
    case Nil{}:
      None{}
    case Con{h, t}:
      qfind.kv(Url.take_to(h, 61), name, u => qfind(t, name))

def qparam(+query: String, +name: String) -> Maybe<&2, String>:
  qfind(String.split(query, '&'), name)

def need.fin(m: Maybe<&2, String>, +name: String) -> Result<&2, &1, Reject, String>:
  match m:
    case None{}:
      Fail{Status{400, "missing query parameter \"" ++ name ++ "\""}}
    case Some{v}:
      Done{v}

def need_param(+query: String, +name: String) -> Result<&2, &1, Reject, String>:
  need.fin(qparam(query, name), name)

def qversion.ok(ok: Bool) -> Result<&2, &1, Reject, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{Status{400, "unsupported connect query parameter: want \"v1\""}}

def qversion.of(m: Maybe<&2, String>) -> Result<&2, &1, Reject, Unit>:
  match m:
    case None{}:
      Done{Unit{}}
    case Some{s}:
      qversion.ok(String.eq(s, "v1"))

# connect=v1 if present, else 400.
def check_qversion(+query: String) -> Result<&2, &1, Reject, Unit>:
  qversion.of(qparam(query, "connect"))

def b64flag.of(m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{s}:
      String.eq(s, "1")

def codec.fin(m: Maybe<&2, Codec>) -> Result<&2, &1, Reject, Codec>:
  match m:
    case None{}:
      Fail{Status{400, "empty encoding query parameter"}}
    case Some{c}:
      Done{c}

def comp.of(m: Maybe<&2, String>) -> Result<&2, &1, Reject, String>:
  match m:
    case None{}:
      Done{"identity"}
    case Some{s}:
      check_enc(s)

def compression_of(+query: String) -> Result<&2, &1, Reject, String>:
  comp.of(qparam(query, "compression"))

# --- url-safe (and standard) base64, padded or not. Private; dedupe with b64.bend later.

def b64val(+c: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)), Some{(c - 65 : U32)},
  Bool.pick(Maybe<&2, U32>, Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Some{(c - 71 : U32)},
  Bool.pick(Maybe<&2, U32>, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Some{(c + 4 : U32)},
  Bool.pick(Maybe<&2, U32>, Bool.or(U32.is_eq(c, 43), U32.is_eq(c, 45)), Some{62},
  Bool.pick(Maybe<&2, U32>, Bool.or(U32.is_eq(c, 47), U32.is_eq(c, 95)), Some{63}, None{})))))

def b64vals.cons(m: Maybe<&2, U32>, r: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match m:
    case None{}:
      None{}
    case Some{v}:
      match r:
        case None{}:
          None{}
        case Some{l}:
          Some{v <> l}

def b64vals(s: String) -> Maybe<&2, List<&2, U32>>:
  match s:
    case SNil{}:
      Some{Nil{}}
    case SCon{Chr{+c}, t}:
      b64vals.cons(b64val(c), b64vals(t))

def b64count(xs: List<&2, U32>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      b64count(t, (acc + 1 : U32))

def b64out(+n: U32) -> U32:
  +r = (n % 4 : U32)
  ((n / 4 : U32) * 3 + r - U32.min(r, 1) : U32)

def b64set(out: Bytes.Bytes, +i: U32, +v: U32) -> Bytes.Bytes:
  Bytes.set(out, i, (v .&. 255 : U32))

# Fills out from the 6-bit values; None on a dangling single char.
def b64go(vs: List<&2, U32>, out: Bytes.Bytes, +i: U32) -> Maybe<&1, Bytes.Bytes>:
  match vs:
    case Nil{}:
      Some{out}
    case Con{+a, Nil{}}:
      None{}
    case Con{+a, Con{+b, Nil{}}}:
      Some{b64set(out, i, ((a << 2n) .|. (b >> 4n) : U32))}
    case Con{+a, Con{+b, Con{+c, Nil{}}}}:
      Some{b64set(b64set(out, i, ((a << 2n) .|. (b >> 4n) : U32)), (i + 1 : U32), (((b .&. 15 : U32) << 4n) .|. (c >> 2n) : U32))}
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      b64go(rest, b64set(b64set(b64set(out, i, ((a << 2n) .|. (b >> 4n) : U32)), (i + 1 : U32), (((b .&. 15 : U32) << 4n) .|. (c >> 2n) : U32)), (i + 2 : U32), (((c .&. 3 : U32) << 6n) .|. d : U32)), (i + 3 : U32))

def b64build(vs: List<&2, U32>, +n: U32) -> Maybe<&1, Bytes.Bytes>:
  b64go(vs, Bytes.new(b64out(n)), 0)

def b64run(m: Maybe<&2, List<&2, U32>>) -> Maybe<&1, Bytes.Bytes>:
  match m:
    case None{}:
      None{}
    case Some{+vs}:
      b64build(vs, b64count(vs, 0))

def b64strip(+s: String) -> String:
  Bool.pick(String, String.ends_with(s, "=="), String.take(s, Nat.sub(String.length(s), 2n)),
    Bool.pick(String, String.ends_with(s, "="), String.take(s, Nat.sub(String.length(s), 1n)), s))

# Decodes RFC 4648 base64 (url-safe or standard alphabet), padding optional.
def b64url_decode(+s: String) -> Maybe<&1, Bytes.Bytes>:
  b64run(b64vals(b64strip(s)))

def msg.bytes(m: Maybe<&1, Bytes.Bytes>) -> Result<&2, &1, Reject, Bytes.Bytes>:
  match m:
    case None{}:
      Fail{Status{400, "invalid base64 in message query parameter"}}
    case Some{b}:
      Done{b}

def msg.kind(b64: Bool, +s: String) -> Result<&2, &1, Reject, Bytes.Bytes>:
  match b64:
    case True{}:
      msg.bytes(b64url_decode(s))
    case False{}:
      Done{Bytes.from_string(s)}

def msg.of(m: Maybe<&2, String>, +b64: Bool) -> Result<&2, &1, Reject, Bytes.Bytes>:
  match m:
    case None{}:
      Fail{Status{400, "invalid percent-encoding in message query parameter"}}
    case Some{s}:
      msg.kind(b64, s)

# message param: percent-decoded, then base64-decoded if base64=1.
def decode_message(+raw: String, +b64: Bool) -> Result<&2, &1, Reject, Bytes.Bytes>:
  msg.of(Url.pct.decode(raw), b64)

def get_req(+path: String, +query: String, +headers: Map<&2, List<&2, String>>, +prefix: String) -> Result<&2, &1, Reject, Spec>:
  do Result<&2, &1, Reject, Spec>:
    proc : String <- parse_proc(path, prefix)
    ok : Unit <- check_version(headers)
    ok2 : Unit <- check_qversion(query)
    es : String <- need_param(query, "encoding")
    codec : Codec <- codec.fin(codec_of(String.to_lower(es)))
    raw : String <- need_param(query, "message")
    msg : Bytes.Bytes <- decode_message(raw, b64flag.of(qparam(query, "base64")))
    +comp : String <- compression_of(query)
    t : Maybe<&2, U32> <- timeout_of(headers)
    return Spec{proc, UnaryGet{}, codec, t, comp, accept_of(headers, "accept-encoding", comp), msg}

# ---------------------------------------------------------------- entry point

def route(post: Bool, get: Bool, +path: String, +query: String, +headers: Map<&2, List<&2, String>>, +prefix: String) -> Result<&2, &1, Reject, Spec>:
  match post:
    case True{}:
      post_req(path, headers, prefix)
    case False{}:
      match get:
        case True{}:
          get_req(path, query, headers, prefix)
        case False{}:
          Fail{Status{405, "method not allowed: want POST or GET"}}

# Classifies a request. method is "POST"/"GET"; query is the raw query string (no '?').
def classify(+method: String, +path: String, +query: String, +headers: Map<&2, List<&2, String>>, +prefix: String) -> Result<&2, &1, Reject, Spec>:
  route(String.eq(method, "POST"), String.eq(method, "GET"), path, query, headers, prefix)
