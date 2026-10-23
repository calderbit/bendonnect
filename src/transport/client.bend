# Connect client transport (bend-kit-http). See src/README-api.md ("Transport -> Client").
#
# Every call returns IO(Result<&1, &1, E.Error, Response>):
#   - transport failures                    -> Fail(Unavailable, <error text>)
#   - unary non-200                         -> Fail(E.from_http(status, body))
#   - stream: error in the EndStreamResponse -> Fail(error)  (messages before it are lost;
#     use server_stream.each to see them as they arrive)
#   - stream without EndStreamResponse      -> Fail(Unknown "missing EndStreamResponse")
# Compressed messages are not supported (Fail Internal): no connect-accept-encoding is sent.
# The stream readers loop on Http.stream.read, which is @unsafe, so those loops are @unsafe too.
import Base
import bend-kit-http@0.36.0.0/http.bend as Http
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-url@0.4.1.0/url.bend as Url
import ../code.bend as Code
import ../error.bend as E
import ../envelope.bend as Env
import ../protocol.bend as P
import ../metadata.bend as Md
import ../b64.bend as B64

type Response is Type:
  Response{headers: Map<&2, List<&2, String>>, trailers: Map<&2, List<&2, String>>, messages: List<&1, Bytes.Bytes>}

# What a finished stream yields: messages (collect mode) and the EndStream metadata.
type Fin is Type:
  Fin{messages: List<&1, Bytes.Bytes>, trailers: Map<&2, List<&2, String>>}

# ------------------------------------------------------------------ helpers

type Item is Type:
  Msg{st: Http.Stream, data: Bytes.Bytes, rest: Bytes.Bytes}
  Over{error: Maybe<&1, E.Error>, metadata: Map<&2, List<&2, String>>}
  Broke{e: E.Error}

def max_message() -> U32:
  16777216

def err.show(e: Http.Err) -> String:
  match e:
    case Http.ErrUrl{}: "invalid URL"
    case Http.ErrDns{}: "DNS resolution failed"
    case Http.ErrConnect{code, why}: "connect failed: " ++ why ++ " (" ++ U32.show(code) ++ ")"
    case Http.ErrTls{code, why}: "TLS failed: " ++ why
    case Http.ErrRead{code, why}: "read failed: " ++ why ++ " (" ++ U32.show(code) ++ ")"
    case Http.ErrWrite{code, why}: "write failed: " ++ why ++ " (" ++ U32.show(code) ++ ")"
    case Http.ErrTimeout{}: "timeout"
    case Http.ErrRedirect{}: "unexpected redirect"
    case Http.ErrBad{}: "malformed HTTP response"

def unavailable(e: Http.Err) -> E.Error:
  E.new(Code.Unavailable{}, err.show(e))

def fail(code: Code.Code, msg: String) -> Result<&1, &1, E.Error, Response>:
  Fail{E.new(code, msg)}

def skip(m: Bytes.Bytes) -> IO(Unit):
  IO.pure(Unit, Unit{})

def url_of(base_url: String, procedure: String) -> String:
  base_url ++ "/" ++ procedure

def req_headers(headers: Map<&2, List<&2, String>>, ct: String) -> Map<&2, List<&2, String>>:
  Http.set(Http.set(headers, "content-type", ct), "connect-protocol-version", "1")

def ct_ok(+headers: Map<&2, List<&2, String>>, expect: String) -> Bool:
  String.eq(P.media(Http.header(headers, "content-type")), expect)

# ------------------------------------------------------------------ unary

def unary.build(ht: Map<&2, List<&2, String>> & Map<&2, List<&2, String>>, body: Bytes.Bytes) -> Response:
  (h, t) = ht
  Response{h, t, [body]}

def unary.status(ok: Bool, ctok: Bool, +status: U32, headers: Map<&2, List<&2, String>>, body: Bytes.Bytes) -> Result<&1, &1, E.Error, Response>:
  match ok:
    case False{}:
      Fail{E.from_http(status, body)}
    case True{}:
      match ctok:
        case False{}:
          fail(Code.Unknown{}, "unexpected response content-type")
        case True{}:
          Done{unary.build(Md.split_trailers(headers), body)}

def unary.res(+codec: P.Codec, res: Http.Res) -> Result<&1, &1, E.Error, Response>:
  Http.Res{+status, +headers, body} = res
  unary.status(U32.is_eq(status, 200), ct_ok(headers, P.unary_content_type(codec)), status, headers, body)

def unary.finish(+codec: P.Codec, r: Result<&1, &1, Http.Err, Http.Res>) -> Result<&1, &1, E.Error, Response>:
  match r:
    case Fail{e}:
      Fail{unavailable(e)}
    case Done{res}:
      unary.res(codec, res)

def unary(base_url: String, procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, msg: Bytes.Bytes) -> IO(Result<&1, &1, E.Error, Response>):
  do IO<Result<&1, &1, E.Error, Response>>:
    r : Result<&1, &1, Http.Err, Http.Res> <- Http.fetch("POST", url_of(base_url, procedure), req_headers(headers, P.unary_content_type(codec)), msg)
    return unary.finish(codec, r)

# ------------------------------------------------------------------ GET

def get.b64(name: String, msg: Bytes.Bytes) -> String:
  "&base64=1&encoding=" ++ Url.pct.encode_q(name) ++ "&message=" ++ B64.encode_url_raw(msg)

# Query order follows the Query-Get rule: connect, base64, compression, encoding, message.
def get.query(+codec: P.Codec, msg: Bytes.Bytes) -> String:
  match codec:
    case P.Json{}:
      "?connect=v1&encoding=json&message=" ++ Url.pct.encode_q(Bytes.to_string(msg))
    case P.Proto{}:
      "?connect=v1" ++ get.b64("proto", msg)
    case P.Custom{name}:
      "?connect=v1" ++ get.b64(name, msg)

def get(base_url: String, procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, msg: Bytes.Bytes) -> IO(Result<&1, &1, E.Error, Response>):
  do IO<Result<&1, &1, E.Error, Response>>:
    r : Result<&1, &1, Http.Err, Http.Res> <- Http.fetch("GET", url_of(base_url, procedure) ++ get.query(codec, msg), headers, Http.from_string(""))
    return unary.finish(codec, r)

# ------------------------------------------------------------------ streaming reads

@unsafe
def drain(st: Http.Stream, acc: Bytes.Bytes) -> IO(Bytes.Bytes):
  do IO<Bytes.Bytes>:
    m : Http.Stream & Result<&1, &1, Http.Err, Maybe<&1, Bytes.Bytes>> <- Http.stream.read(st)
    drain.step(m, acc)

@unsafe
def drain.step(m: Http.Stream & Result<&1, &1, Http.Err, Maybe<&1, Bytes.Bytes>>, acc: Bytes.Bytes) -> IO(Bytes.Bytes):
  (st, r) = m
  match r:
    case Fail{e}:
      do IO<Bytes.Bytes>:
        Http.stream.close(st)
        return acc
    case Done{mb}:
      match mb:
        case None{}:
          do IO<Bytes.Bytes>:
            Http.stream.close(st)
            return acc
        case Some{b}:
          drain(st, Bytes.append(acc, b))

def emit(~on_msg: Bytes.Bytes -> IO(Unit), collect: Bool, m: Bytes.Bytes, acc: List<&1, Bytes.Bytes>) -> IO(List<&1, Bytes.Bytes>):
  match collect:
    case True{}:
      IO.pure(List<&1, Bytes.Bytes>, m <> acc)
    case False{}:
      do IO<List<&1, Bytes.Bytes>>:
        on_msg(m)
        return acc

def end.done(error: Maybe<&1, E.Error>, metadata: Map<&2, List<&2, String>>, acc: List<&1, Bytes.Bytes>) -> Result<&1, &1, E.Error, Fin>:
  match error:
    case Some{e}:
      Fail{e}
    case None{}:
      Done{Fin{List.reverse(&1, Bytes.Bytes, acc), metadata}}

def broke(code: Code.Code, msg: String) -> Item:
  Broke{E.new(code, msg)}

def over.es(es: E.EndStream) -> Item:
  E.EndStream{error, metadata} = es
  Over{error, metadata}

def over.of(m: Maybe<&1, E.EndStream>) -> Item:
  match m:
    case None{}:
      broke(Code.Internal{}, "invalid EndStreamResponse")
    case Some{es}:
      over.es(es)

def recv.last(st: Http.Stream, last: Bool, data: Bytes.Bytes, rest: Bytes.Bytes) -> IO(Item):
  match last:
    case True{}:
      do IO<Item>:
        Http.stream.close(st)
        return over.of(E.end_decode(data))
    case False{}:
      IO.pure(Item, Msg{st, data, rest})

def recv.cls(st: Http.Stream, compressed: Bool, last: Bool, data: Bytes.Bytes, rest: Bytes.Bytes) -> IO(Item):
  match compressed:
    case True{}:
      do IO<Item>:
        Http.stream.close(st)
        return broke(Code.Internal{}, "compressed message but no encoding was negotiated")
    case False{}:
      recv.last(st, last, data, rest)

def recv.env(st: Http.Stream, env: Env.Envelope, rest: Bytes.Bytes) -> IO(Item):
  Env.Envelope{+flags, data} = env
  recv.cls(st, U32.is_ne((flags .&. 1 : U32), 0), U32.is_ne((flags .&. 2 : U32), 0), data, rest)

# Reads from the wire until one whole envelope is buffered, then classifies it. The stream
# is closed whenever the item is Over or Broke. (Http.stream.read is unsafe, so these are.)
@unsafe
def recv(st: Http.Stream, buf: Bytes.Bytes) -> IO(Item):
  recv.step(st, Env.decode(buf, max_message()))

@unsafe
def recv.step(st: Http.Stream, step: Env.Step) -> IO(Item):
  match step:
    case Env.Need{buf}:
      do IO<Item>:
        m : Http.Stream & Result<&1, &1, Http.Err, Maybe<&1, Bytes.Bytes>> <- Http.stream.read(st)
        recv.read(m, buf)
    case Env.Got{env, rest}:
      recv.env(st, env, rest)
    case Env.Bad{reason}:
      do IO<Item>:
        Http.stream.close(st)
        return broke(Code.Internal{}, reason)

@unsafe
def recv.read(m: Http.Stream & Result<&1, &1, Http.Err, Maybe<&1, Bytes.Bytes>>, buf: Bytes.Bytes) -> IO(Item):
  (st, r) = m
  match r:
    case Fail{e}:
      do IO<Item>:
        Http.stream.close(st)
        return Broke{unavailable(e)}
    case Done{mb}:
      match mb:
        case None{}:
          do IO<Item>:
            Http.stream.close(st)
            return broke(Code.Unknown{}, "missing EndStreamResponse")
        case Some{b}:
          recv(st, Bytes.append(buf, b))

# The callback loop: one self-recursive template (templates cannot be mutually recursive).
@unsafe
def pump(~on_msg: Bytes.Bytes -> IO(Unit), +collect: Bool, item: Item, acc: List<&1, Bytes.Bytes>) -> IO(Result<&1, &1, E.Error, Fin>):
  match item:
    case Msg{st, data, rest}:
      do IO<Result<&1, &1, E.Error, Fin>>:
        acc2 : List<&1, Bytes.Bytes> <- emit(~on_msg, collect, data, acc)
        next : Item <- recv(st, rest)
        pump(~on_msg, collect, next, acc2)
    case Over{error, metadata}:
      IO.pure(Result<&1, &1, E.Error, Fin>, end.done(error, metadata, acc))
    case Broke{e}:
      IO.pure(Result<&1, &1, E.Error, Fin>, Fail{e})

# ------------------------------------------------------------------ response head

def done.build(ht: Map<&2, List<&2, String>> & Map<&2, List<&2, String>>, f: Fin) -> Response:
  (h, extra) = ht
  Fin{messages, trailers} = f
  Response{h, trailers, messages}

def done(headers: Map<&2, List<&2, String>>, r: Result<&1, &1, E.Error, Fin>) -> Result<&1, &1, E.Error, Response>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{f}:
      Done{done.build(Md.split_trailers(headers), f)}

def head.ok(~on_msg: Bytes.Bytes -> IO(Unit), collect: Bool, ctok: Bool, st: Http.Stream, headers: Map<&2, List<&2, String>>) -> IO(Result<&1, &1, E.Error, Response>):
  match ctok:
    case False{}:
      do IO<Result<&1, &1, E.Error, Response>>:
        Http.stream.close(st)
        return fail(Code.Unknown{}, "unexpected response content-type")
    case True{}:
      do IO<Result<&1, &1, E.Error, Response>>:
        first : Item <- recv(st, Bytes.new(0))
        r : Result<&1, &1, E.Error, Fin> <- pump(~on_msg, collect, first, Nil{})
        return done(headers, r)

def head.status(~on_msg: Bytes.Bytes -> IO(Unit), collect: Bool, ok: Bool, ctok: Bool, +status: U32, st: Http.Stream, headers: Map<&2, List<&2, String>>) -> IO(Result<&1, &1, E.Error, Response>):
  match ok:
    case True{}:
      head.ok(~on_msg, collect, ctok, st, headers)
    case False{}:
      do IO<Result<&1, &1, E.Error, Response>>:
        body : Bytes.Bytes <- drain(st, Bytes.new(0))
        return Fail{E.from_http(status, body)}

def head.of(~on_msg: Bytes.Bytes -> IO(Unit), collect: Bool, expect: String, m: Http.Stream & Http.Res) -> IO(Result<&1, &1, E.Error, Response>):
  (st, res) = m
  Http.Res{+status, +headers, body} = res
  head.status(~on_msg, collect, U32.is_eq(status, 200), ct_ok(headers, expect), status, st, headers)

def opened(~on_msg: Bytes.Bytes -> IO(Unit), collect: Bool, +codec: P.Codec, r: Result<&1, &1, Http.Err, Http.Stream>) -> IO(Result<&1, &1, E.Error, Response>):
  match r:
    case Fail{e}:
      IO.pure(Result<&1, &1, E.Error, Response>, Fail{unavailable(e)})
    case Done{st}:
      head.of(~on_msg, collect, P.stream_content_type(codec), Http.stream.res(st))

# ------------------------------------------------------------------ server stream

def ss.run(~on_msg: Bytes.Bytes -> IO(Unit), collect: Bool, base_url: String, procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, msg: Bytes.Bytes) -> IO(Result<&1, &1, E.Error, Response>):
  do IO<Result<&1, &1, E.Error, Response>>:
    r : Result<&1, &1, Http.Err, Http.Stream> <- Http.open("POST", url_of(base_url, procedure), req_headers(headers, P.stream_content_type(codec)), Env.encode(Env.Envelope{0, msg}))
    opened(~on_msg, collect, codec, r)

def server_stream(base_url: String, procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, msg: Bytes.Bytes) -> IO(Result<&1, &1, E.Error, Response>):
  ss.run(~skip, True{}, base_url, procedure, codec, headers, msg)

# Like server_stream, but calls on_msg for every message as it arrives (messages in the
# returned Response is empty). An error end-stream still yields Fail after the callbacks ran.
def server_stream.each(~on_msg: Bytes.Bytes -> IO(Unit), base_url: String, procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, msg: Bytes.Bytes) -> IO(Result<&1, &1, E.Error, Response>):
  ss.run(~on_msg, False{}, base_url, procedure, codec, headers, msg)

# ------------------------------------------------------------------ client stream

@unsafe
def upload.next(t: List<&1, Bytes.Bytes>, m: Http.Up & Result<&2, &2, Http.Err, Unit>) -> IO(Http.Up):
  (up2, wr) = m
  upload.all(up2, t)

@unsafe
def upload.all(up: Http.Up, msgs: List<&1, Bytes.Bytes>) -> IO(Http.Up):
  match msgs:
    case Nil{}:
      IO.pure(Http.Up, up)
    case Con{h, t}:
      do IO<Http.Up>:
        m : Http.Up & Result<&2, &2, Http.Err, Unit> <- Http.upload.write(up, Env.encode(Env.Envelope{0, h}))
        upload.next(t, m)

def one(r: Result<&1, &1, E.Error, Response>) -> Result<&1, &1, E.Error, Response>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{resp}:
      Response{h, t, ms} = resp
      match ms:
        case Nil{}:
          fail(Code.Unknown{}, "client stream: no response message")
        case Con{m, rest}:
          match rest:
            case Nil{}:
              Done{Response{h, t, [m]}}
            case Con{x, y}:
              fail(Code.Unknown{}, "client stream: more than one response message")

def cs.sent(+codec: P.Codec, fr: Result<&1, &1, Http.Err, Http.Stream>) -> IO(Result<&1, &1, E.Error, Response>):
  do IO<Result<&1, &1, E.Error, Response>>:
    r : Result<&1, &1, E.Error, Response> <- opened(~skip, True{}, codec, fr)
    return one(r)

def cs.open(+codec: P.Codec, msgs: List<&1, Bytes.Bytes>, r: Result<&1, &1, Http.Err, Http.Up>) -> IO(Result<&1, &1, E.Error, Response>):
  match r:
    case Fail{e}:
      IO.pure(Result<&1, &1, E.Error, Response>, Fail{unavailable(e)})
    case Done{up}:
      do IO<Result<&1, &1, E.Error, Response>>:
        up2 : Http.Up <- upload.all(up, msgs)
        fr : Result<&1, &1, Http.Err, Http.Stream> <- Http.upload.finish(up2)
        cs.sent(codec, fr)

# Each message is one chunked-upload write holding one envelope. A failed write surfaces
# from upload.finish.
def client_stream(base_url: String, procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, msgs: List<&1, Bytes.Bytes>) -> IO(Result<&1, &1, E.Error, Response>):
  do IO<Result<&1, &1, E.Error, Response>>:
    r : Result<&1, &1, Http.Err, Http.Up> <- Http.upload("POST", url_of(base_url, procedure), req_headers(headers, P.stream_content_type(codec)))
    cs.open(codec, msgs, r)
