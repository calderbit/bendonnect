# Connect Error and EndStreamResponse (JSON). Pure.
# See https://connectrpc.com/docs/protocol/#error-end-stream
#
# DEVIATION: Detail.type is a Bend keyword, so the field is named type_name.
#
# Wire shapes:
#   Error:     {"code":"unavailable","message":"..","details":[{"type":"..","value":"<unpadded b64>","debug":{..}}]}
#              message/details are omitted when empty; "debug" only when present.
#   EndStream: {"error":{..},"metadata":{"k":["v"]}}  ({} on success with no metadata)
#
# Decoding notes: details whose type/value is missing or whose value is not
# valid base64 are dropped (clients must not rely on details). Metadata keys
# are lowercased; metadata entries that are not arrays are skipped.
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-encoding@0.4.0.0/encoding.bend as Enc
import bend-kit-json@0.6.1.1/json.bend as Json
import ./code.bend as Code
import ./b64.bend as B64

type Detail is Type:
  Detail{type_name: String, value: Bytes.Bytes, debug: Maybe<&1, Json.Val>}

type Error is Type:
  Error{code: Code.Code, message: String, details: List<&1, Detail>}

type EndStream is Type:
  EndStream{error: Maybe<&1, Error>, metadata: Map<&2, List<&2, String>>}

def new(code: Code.Code, message: String) -> Error:
  Error{code, message, Nil{}}

# ---------------------------------------------------------------- helpers

def str_val(+s: String) -> Json.Val:
  Json.Str{Enc.utf8.encode(s)}

def kv(+k: String, v: Json.Val) -> Bytes.Bytes & Json.Val:
  (Enc.utf8.encode(k), v)

# ---------------------------------------------------------------- encoding

def debug_part(m: Maybe<&1, Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  match m:
    case None{}:
      Nil{}
    case Some{v}:
      Con{kv("debug", v), Nil{}}

def detail_to_json(d: Detail) -> Json.Val:
  Detail{+ty, value, debug} = d
  Json.Obj{Con{kv("type", str_val(ty)), Con{kv("value", str_val(B64.encode_std_raw(value))), debug_part(debug)}}}

def details_json(ds: List<&1, Detail>) -> List<&1, Json.Val>:
  match ds:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{detail_to_json(h), details_json(t)}

def details_part(ds: List<&1, Detail>, rest: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  match ds:
    case Nil{}:
      rest
    case Con{h, t}:
      Con{kv("details", Json.Arr{Con{detail_to_json(h), details_json(t)}}), rest}

def message_part.go(empty: Bool, m: String, rest: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  match empty:
    case True{}:
      rest
    case False{}:
      Con{kv("message", str_val(m)), rest}

def message_part(+m: String, rest: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  message_part.go(String.is_empty(m), m, rest)

def to_json(e: Error) -> Json.Val:
  Error{code, message, details} = e
  Json.Obj{Con{kv("code", str_val(Code.to_string(code))), message_part(message, details_part(details, Nil{}))}}

def encode(e: Error) -> Bytes.Bytes:
  Json.encode.bytes(to_json(e))

# ---------------------------------------------------------------- decoding

# Up to three fields picked out of an object by name.
type Fs is Type:
  Fs{a: Maybe<&1, Json.Val>, b: Maybe<&1, Json.Val>, c: Maybe<&1, Json.Val>}

def fs.empty() -> Fs:
  Fs{None{}, None{}, None{}}

def put1(v: Json.Val, f: Fs) -> Fs:
  Fs{a, b, c} = f
  Fs{Some{v}, b, c}

def put2(v: Json.Val, f: Fs) -> Fs:
  Fs{a, b, c} = f
  Fs{a, Some{v}, c}

def put3(v: Json.Val, f: Fs) -> Fs:
  Fs{a, b, c} = f
  Fs{a, b, Some{v}}

def pick.put3(i3: Bool, v: Json.Val, f: Fs) -> Fs:
  match i3:
    case True{}:
      put3(v, f)
    case False{}:
      f

def pick.put2(i2: Bool, i3: Bool, v: Json.Val, f: Fs) -> Fs:
  match i2:
    case True{}:
      put2(v, f)
    case False{}:
      pick.put3(i3, v, f)

def pick.put(i1: Bool, i2: Bool, i3: Bool, v: Json.Val, f: Fs) -> Fs:
  match i1:
    case True{}:
      put1(v, f)
    case False{}:
      pick.put2(i2, i3, v, f)

def pick.slot(+ks: String, +n1: String, +n2: String, +n3: String, v: Json.Val, f: Fs) -> Fs:
  pick.put(String.eq(ks, n1), String.eq(ks, n2), String.eq(ks, n3), v, f)

def pick.go(kvs: List<&1, Bytes.Bytes & Json.Val>, +n1: String, +n2: String, +n3: String, f: Fs) -> Fs:
  match kvs:
    case Nil{}:
      f
    case Con{p, rest}:
      (k, v) = p
      pick.go(rest, n1, n2, n3, pick.slot(Enc.utf8.decode(k), n1, n2, n3, v, f))

def unknown_of(m: Maybe<&2, Code.Code>) -> Code.Code:
  match m:
    case None{}:
      Code.Unknown{}
    case Some{c}:
      c

def code_str(s: Bytes.Bytes) -> Maybe<&2, Code.Code>:
  Some{unknown_of(Code.from_string(Enc.utf8.decode(s)))}

def code_of.val(v: Json.Val) -> Maybe<&2, Code.Code>:
  match v:
    case Json.Str{s}:
      code_str(s)
    case Json.Null{}:
      None{}
    case Json.Flag{on}:
      None{}
    case Json.Num{s}:
      None{}
    case Json.Arr{xs}:
      None{}
    case Json.Obj{kvs}:
      None{}

# A present string code (unrecognized names become Unknown); anything else is None.
def code_of(m: Maybe<&1, Json.Val>) -> Maybe<&2, Code.Code>:
  match m:
    case None{}:
      None{}
    case Some{v}:
      code_of.val(v)

def str_of.val(v: Json.Val) -> String:
  match v:
    case Json.Str{s}:
      Enc.utf8.decode(s)
    case Json.Null{}:
      ""
    case Json.Flag{on}:
      ""
    case Json.Num{s}:
      ""
    case Json.Arr{xs}:
      ""
    case Json.Obj{kvs}:
      ""

def str_of(m: Maybe<&1, Json.Val>) -> String:
  match m:
    case None{}:
      ""
    case Some{v}:
      str_of.val(v)

def opt_str.val(v: Json.Val) -> Maybe<&2, String>:
  match v:
    case Json.Str{s}:
      Some{Enc.utf8.decode(s)}
    case Json.Null{}:
      None{}
    case Json.Flag{on}:
      None{}
    case Json.Num{s}:
      None{}
    case Json.Arr{xs}:
      None{}
    case Json.Obj{kvs}:
      None{}

def opt_str(m: Maybe<&1, Json.Val>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{v}:
      opt_str.val(v)

def opt_b64(m: Maybe<&2, String>) -> Maybe<&1, Bytes.Bytes>:
  match m:
    case None{}:
      None{}
    case Some{+s}:
      B64.decode(s)

def detail_build(ty: Maybe<&2, String>, vb: Maybe<&1, Bytes.Bytes>, debug: Maybe<&1, Json.Val>) -> Maybe<&1, Detail>:
  match ty vb:
    case Some{t} Some{b}:
      Some{Detail{t, b, debug}}
    case _ _:
      None{}

def detail_fields(f: Fs) -> Maybe<&1, Detail>:
  Fs{a, b, c} = f
  detail_build(opt_str(a), opt_b64(opt_str(b)), c)

def detail_of(v: Json.Val) -> Maybe<&1, Detail>:
  match v:
    case Json.Obj{kvs}:
      detail_fields(pick.go(kvs, "type", "value", "debug", fs.empty()))
    case Json.Null{}:
      None{}
    case Json.Flag{on}:
      None{}
    case Json.Num{s}:
      None{}
    case Json.Str{s}:
      None{}
    case Json.Arr{xs}:
      None{}

def details_push(m: Maybe<&1, Detail>, rest: List<&1, Detail>) -> List<&1, Detail>:
  match m:
    case Some{d}:
      Con{d, rest}
    case None{}:
      rest

def details_go(xs: List<&1, Json.Val>) -> List<&1, Detail>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      details_push(detail_of(h), details_go(t))

def details_val(v: Json.Val) -> List<&1, Detail>:
  match v:
    case Json.Arr{xs}:
      details_go(xs)
    case Json.Null{}:
      Nil{}
    case Json.Flag{on}:
      Nil{}
    case Json.Num{s}:
      Nil{}
    case Json.Str{s}:
      Nil{}
    case Json.Obj{kvs}:
      Nil{}

def details_of(m: Maybe<&1, Json.Val>) -> List<&1, Detail>:
  match m:
    case None{}:
      Nil{}
    case Some{v}:
      details_val(v)

def error_build(c: Maybe<&2, Code.Code>, msg: String, ds: List<&1, Detail>) -> Maybe<&1, Error>:
  match c:
    case None{}:
      None{}
    case Some{code}:
      Some{Error{code, msg, ds}}

def error_fields(f: Fs) -> Maybe<&1, Error>:
  Fs{a, b, c} = f
  error_build(code_of(a), str_of(b), details_of(c))

# {}, {"code":null}, a non-string code, or a non-object are invalid (None).
def from_json(v: Json.Val) -> Maybe<&1, Error>:
  match v:
    case Json.Obj{kvs}:
      error_fields(pick.go(kvs, "code", "message", "details", fs.empty()))
    case Json.Null{}:
      None{}
    case Json.Flag{on}:
      None{}
    case Json.Num{s}:
      None{}
    case Json.Str{s}:
      None{}
    case Json.Arr{xs}:
      None{}

def decode.val(m: Maybe<&1, Json.Val>) -> Maybe<&1, Error>:
  match m:
    case None{}:
      None{}
    case Some{v}:
      from_json(v)

def decode(b: Bytes.Bytes) -> Maybe<&1, Error>:
  decode.val(Json.parse.bytes(b))

# ---------------------------------------------------------------- client: from_http

def status_text(+s: U32) -> String:
  Bool.pick(String, U32.is_eq(s, 400), "Bad Request",
  Bool.pick(String, U32.is_eq(s, 401), "Unauthorized",
  Bool.pick(String, U32.is_eq(s, 403), "Forbidden",
  Bool.pick(String, U32.is_eq(s, 404), "Not Found",
  Bool.pick(String, U32.is_eq(s, 429), "Too Many Requests",
  Bool.pick(String, U32.is_eq(s, 500), "Internal Server Error",
  Bool.pick(String, U32.is_eq(s, 502), "Bad Gateway",
  Bool.pick(String, U32.is_eq(s, 503), "Service Unavailable",
  Bool.pick(String, U32.is_eq(s, 504), "Gateway Timeout",
  String.append("HTTP ", U32.show(s)))))))))))

def from_http.pick(m: Maybe<&1, Error>, +status: U32) -> Error:
  match m:
    case Some{e}:
      e
    case None{}:
      Error{Code.from_http(status), status_text(status), Nil{}}

# Client side of a non-200 unary response: the Connect error in the body if
# it parses, else a code inferred from the status with the status text as message.
def from_http(+status: U32, body: Bytes.Bytes) -> Error:
  from_http.pick(decode(body), status)

# ---------------------------------------------------------------- EndStream

def strs_val(vs: List<&2, String>) -> List<&1, Json.Val>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{str_val(h), strs_val(t)}

def meta_entries(xs: List<&2, Sigma<&2, &2, String, _ => List<&2, String>>>) -> List<&1, Bytes.Bytes & Json.Val>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Tuple{+k, v}, rest}:
      Con{kv(k, Json.Arr{strs_val(v)}), meta_entries(rest)}

def meta_part(xs: List<&2, Sigma<&2, &2, String, _ => List<&2, String>>>) -> List<&1, Bytes.Bytes & Json.Val>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{kv("metadata", Json.Obj{meta_entries(Con{h, t})}), Nil{}}

def err_part(e: Maybe<&1, Error>, rest: List<&1, Bytes.Bytes & Json.Val>) -> List<&1, Bytes.Bytes & Json.Val>:
  match e:
    case None{}:
      rest
    case Some{x}:
      Con{kv("error", to_json(x)), rest}

def end_encode(e: EndStream) -> Bytes.Bytes:
  EndStream{error, metadata} = e
  Json.encode.bytes(Json.Obj{err_part(error, meta_part(Map.to_list(&2, List<&2, String>, metadata)))})

def strs_push(v: Json.Val, rest: List<&2, String>) -> List<&2, String>:
  match v:
    case Json.Str{s}:
      Con{Enc.utf8.decode(s), rest}
    case Json.Null{}:
      rest
    case Json.Flag{on}:
      rest
    case Json.Num{s}:
      rest
    case Json.Arr{xs}:
      rest
    case Json.Obj{kvs}:
      rest

def strs_of(xs: List<&1, Json.Val>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      strs_push(h, strs_of(t))

def meta_set(+k: String, v: Json.Val, acc: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match v:
    case Json.Arr{xs}:
      Map.set(&2, List<&2, String>, acc, String.to_lower(k), strs_of(xs))
    case Json.Null{}:
      acc
    case Json.Flag{on}:
      acc
    case Json.Num{s}:
      acc
    case Json.Str{s}:
      acc
    case Json.Obj{kvs}:
      acc

def meta_map(kvs: List<&1, Bytes.Bytes & Json.Val>, acc: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match kvs:
    case Nil{}:
      acc
    case Con{p, rest}:
      (k, v) = p
      meta_map(rest, meta_set(Enc.utf8.decode(k), v, acc))

def meta_val(v: Json.Val) -> Maybe<&2, Map<&2, List<&2, String>>>:
  match v:
    case Json.Obj{kvs}:
      Some{meta_map(kvs, Map.new(&2, List<&2, String>))}
    case Json.Null{}:
      Some{Map.new(&2, List<&2, String>)}
    case Json.Flag{on}:
      None{}
    case Json.Num{s}:
      None{}
    case Json.Str{s}:
      None{}
    case Json.Arr{xs}:
      None{}

def meta_of(m: Maybe<&1, Json.Val>) -> Maybe<&2, Map<&2, List<&2, String>>>:
  match m:
    case None{}:
      Some{Map.new(&2, List<&2, String>)}
    case Some{v}:
      meta_val(v)

# absent error is fine (Some None); present-but-invalid error is None.
def err_val(m: Maybe<&1, Error>) -> Maybe<&1, Maybe<&1, Error>>:
  match m:
    case None{}:
      None{}
    case Some{e}:
      Some{Some{e}}

def err_of(m: Maybe<&1, Json.Val>) -> Maybe<&1, Maybe<&1, Error>>:
  match m:
    case None{}:
      Some{None{}}
    case Some{v}:
      err_val(from_json(v))

def end_build(e: Maybe<&1, Maybe<&1, Error>>, m: Maybe<&2, Map<&2, List<&2, String>>>) -> Maybe<&1, EndStream>:
  match e m:
    case Some{err} Some{md}:
      Some{EndStream{err, md}}
    case _ _:
      None{}

def end_fields(f: Fs) -> Maybe<&1, EndStream>:
  Fs{a, b, c} = f
  end_build(err_of(a), meta_of(b))

def end_from_json(v: Json.Val) -> Maybe<&1, EndStream>:
  match v:
    case Json.Obj{kvs}:
      end_fields(pick.go(kvs, "error", "metadata", "_", fs.empty()))
    case Json.Null{}:
      None{}
    case Json.Flag{on}:
      None{}
    case Json.Num{s}:
      None{}
    case Json.Str{s}:
      None{}
    case Json.Arr{xs}:
      None{}

def end_decode.val(m: Maybe<&1, Json.Val>) -> Maybe<&1, EndStream>:
  match m:
    case None{}:
      None{}
    case Some{v}:
      end_from_json(v)

# {"error":null}, {"error":{}} and {"error":{"code":null}} are invalid (None).
def end_decode(b: Bytes.Bytes) -> Maybe<&1, EndStream>:
  end_decode.val(Json.parse.bytes(b))
