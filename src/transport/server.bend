# Connect server transport on bend-kit-http's serve.write.* (HTTP/1.1 only).
# Request bodies are buffered before the handler runs (no client/bidi streaming); responses are
# written incrementally (server streaming). Unary and error replies use a known length so the body
# is not chunked. Run it with `bend file.bend` (runner) or a native build (`bend f.bend -o f`).
import Base
import bend-kit-http@0.36.0.0/http.bend as Http
import bend-kit-http@0.36.0.0/completion.bend as Completion
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ../code.bend as Code
import ../error.bend as E
import ../metadata.bend as Md
import ../envelope.bend as Env
import ../protocol.bend as P

# ---------------------------------------------------------------- public API

type Meta is Data:
  Meta{headers: Map<&2, List<&2, String>>, trailers: Map<&2, List<&2, String>>}

type Call is Type:
  Call{procedure: String, kind: P.CallKind, codec: P.Codec, headers: Map<&2, List<&2, String>>,
    timeout_ms: Maybe<&2, U32>, messages: List<&1, Bytes.Bytes>}

# Wraps the HTTP writer of a server stream.
type Sink is Type:
  Sink{w: Http.Writer}

type Reply is Type:
  Single{result: Result<&1, &1, E.Error, Bytes.Bytes>, meta: Meta}
  Many{run: Sink -> IO(Sink & Result<&1, &1, E.Error, Unit>), meta: Meta}
  NoRoute{}

def meta.empty() -> Meta:
  Meta{Map.new(&2, List<&2, String>), Map.new(&2, List<&2, String>)}

def ok(msg: Bytes.Bytes) -> Reply:
  Single{Done{msg}, meta.empty()}

def fail(code: Code.Code, message: String) -> Reply:
  Single{Fail{E.new(code, message)}, meta.empty()}

# One enveloped message, written (and flushed) immediately.
def send(sink: Sink, msg: Bytes.Bytes) -> IO(Sink):
  Sink{w} = sink
  do IO<Sink>:
    w2 : Http.Writer <- Http.writer.write(w, Env.encode(Env.Envelope{0, msg}))
    return Sink{w2}

# ---------------------------------------------------------------- internals

# Per-request state carried from `start` to `write`.
type Job is Type:
  JBytes{body: Bytes.Bytes}
  JMany{run: Sink -> IO(Sink & Result<&1, &1, E.Error, Unit>), trailers: Map<&2, List<&2, String>>}

# Result of the pure half of `start`.
type Pre is Type:
  PEarly{status: U32, headers: Map<&2, List<&2, String>>, body: Bytes.Bytes}
  PReady{call: Call, timeout: Maybe<&2, U32>, stream: Bool, codec: P.Codec}

def msg_max() -> U32:
  4194304

def merge.go(xs: List<&2, Sigma<&2, &2, String, _ => List<&2, String>>>, acc: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match xs:
    case Nil{}:
      acc
    case Con{Tuple{k, v}, rest}:
      merge.go(rest, Map.set(&2, List<&2, String>, acc, k, v))

def merge(a: Map<&2, List<&2, String>>, b: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  merge.go(Map.to_list(&2, List<&2, String>, b), a)

def end_env(e: Maybe<&1, E.Error>, trailers: Map<&2, List<&2, String>>) -> Bytes.Bytes:
  Env.encode(Env.Envelope{Env.flag_end(), E.end_encode(E.EndStream{e, trailers})})

def end_bytes(res: Result<&1, &1, E.Error, Unit>, trailers: Map<&2, List<&2, String>>) -> Bytes.Bytes:
  match res:
    case Fail{e}:
      end_env(Some{e}, trailers)
    case Done{u}:
      end_env(None{}, trailers)

def json_hdr() -> Map<&2, List<&2, String>>:
  Http.set(Http.empty(), "content-type", "application/json")

def head(status: U32, headers: Map<&2, List<&2, String>>, body: Bytes.Bytes) -> IO(Http.WriteHead<Job>):
  Bytes.Bytes{+len, buf} = body
  IO.pure(Http.WriteHead<Job>, Http.WriteHead{status, headers, Some{len}, JBytes{Bytes.Bytes{len, buf}}, Completion.Unobserved{}})

def err_status(e: E.Error) -> U32:
  E.Error{+code, message, details} = e
  Code.to_http(code)

# HTTP-level error (unary style): status from the code, JSON body.
def early_json(e: E.Error) -> Pre:
  E.Error{+code, +message, details} = e
  PEarly{Code.to_http(code), json_hdr(), E.encode(E.Error{code, message, details})}

# Streaming-style error: 200 + a single EndStream envelope.
def early_stream(c: P.Codec, e: E.Error) -> Pre:
  PEarly{200, Http.set(Http.empty(), "content-type", P.stream_content_type(c)), end_env(Some{e}, Map.new(&2, List<&2, String>))}

def early.pick(stream: Bool, c: P.Codec, e: E.Error) -> Pre:
  match stream:
    case True{}:
      early_stream(c, e)
    case False{}:
      early_json(e)

def reject_pre(r: P.Reject, stream: Bool, c: P.Codec) -> Pre:
  match r:
    case P.Status{+s, +m}:
      PEarly{s, json_hdr(), E.encode(E.new(Code.from_http(s), m))}
    case P.Connect{code, m}:
      early.pick(stream, c, E.new(code, m))

# --- request envelopes -> messages

def env_flags_ok(+flags: U32) -> Bool:
  U32.is_eq(flags, 0)

def msgs.cons(m: Bytes.Bytes, r: Result<&1, &1, E.Error, List<&1, Bytes.Bytes>>) -> Result<&1, &1, E.Error, List<&1, Bytes.Bytes>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{xs}:
      Done{m <> xs}

def msgs.one(ok: Bool, data: Bytes.Bytes, rest: Result<&1, &1, E.Error, List<&1, Bytes.Bytes>>) -> Result<&1, &1, E.Error, List<&1, Bytes.Bytes>>:
  match ok:
    case True{}:
      msgs.cons(data, rest)
    case False{}:
      Fail{E.new(Code.InvalidArgument{}, "unexpected envelope flags in request (compression or end-stream with identity encoding)")}

def msgs(envs: List<&1, Env.Envelope>) -> Result<&1, &1, E.Error, List<&1, Bytes.Bytes>>:
  match envs:
    case Nil{}:
      Done{Nil{}}
    case Con{Env.Envelope{+flags, data}, rest}:
      msgs.one(env_flags_ok(flags), data, msgs(rest))

def too_big(+reason: String) -> Bool:
  String.starts_with(reason, "message size")

def decode_err(+reason: String) -> E.Error:
  E.new(Bool.pick(Code.Code, too_big(reason), Code.ResourceExhausted{}, Code.InvalidArgument{}), reason)

# --- building the Call

def ready(procedure: String, kind: P.CallKind, +codec: P.Codec, headers: Map<&2, List<&2, String>>, +t: Maybe<&2, U32>, stream: Bool, ms: List<&1, Bytes.Bytes>) -> Pre:
  PReady{Call{procedure, kind, codec, headers, t, ms}, t, stream, codec}

def stream_done(procedure: String, codec: P.Codec, headers: Map<&2, List<&2, String>>, t: Maybe<&2, U32>, r: Result<&1, &1, E.Error, List<&1, Bytes.Bytes>>) -> Pre:
  match r:
    case Fail{e}:
      early_stream(codec, e)
    case Done{ms}:
      ready(procedure, P.Stream{}, codec, headers, t, True{}, ms)

def stream_decoded(procedure: String, codec: P.Codec, headers: Map<&2, List<&2, String>>, t: Maybe<&2, U32>, r: Result<&2, &1, String, List<&1, Env.Envelope>>) -> Pre:
  match r:
    case Fail{reason}:
      early_stream(codec, decode_err(reason))
    case Done{envs}:
      stream_done(procedure, codec, headers, t, msgs(envs))

def build.go(kind: P.CallKind, procedure: String, codec: P.Codec, t: Maybe<&2, U32>, message: Bytes.Bytes, headers: Map<&2, List<&2, String>>, body: Bytes.Bytes) -> Pre:
  match kind:
    case P.Unary{}:
      ready(procedure, P.Unary{}, codec, headers, t, False{}, body <> Nil{})
    case P.UnaryGet{}:
      ready(procedure, P.UnaryGet{}, codec, headers, t, False{}, message <> Nil{})
    case P.Stream{}:
      stream_decoded(procedure, codec, headers, t, Env.decode_all(body, msg_max()))

def build(spec: P.Spec, headers: Map<&2, List<&2, String>>, body: Bytes.Bytes) -> Pre:
  P.Spec{procedure, kind, codec, timeout_ms, encoding, accept, message} = spec
  build.go(kind, procedure, codec, timeout_ms, message, headers, body)

def pre.go(r: Result<&2, &1, P.Reject, P.Spec>, headers: Map<&2, List<&2, String>>, body: Bytes.Bytes, ct: P.Ct) -> Pre:
  match r:
    case Fail{rej}:
      P.Ct{+stream, +codec} = ct
      reject_pre(rej, stream, codec)
    case Done{spec}:
      build(spec, headers, body)

# Content type -> (stream?, codec), used only to shape rejections. Falls back to unary JSON.
def ct_of.fin(m: Maybe<&2, P.Ct>) -> P.Ct:
  match m:
    case None{}:
      P.Ct{False{}, P.Json{}}
    case Some{c}:
      c

def ct_of(+h: Map<&2, List<&2, String>>) -> P.Ct:
  ct_of.fin(P.parse_content_type(Http.header(h, "content-type")))

def split_q.cons(c: U32, r: String & String) -> String & String:
  (a, b) = r
  (SCon{Chr{c}, a}, b)

def split_q.pick(hit: Bool, +c: U32, +t: String, rest: Unit -> String & String) -> String & String:
  match hit:
    case True{}:
      ("", t)
    case False{}:
      split_q.cons(c, rest(Unit{}))

# "/p/q?a=b" -> ("/p/q", "a=b")
def split_q(+s: String) -> String & String:
  match s:
    case SNil{}:
      ("", "")
    case SCon{Chr{+c}, +t}:
      split_q.pick(U32.is_eq(c, 63), c, t, u => split_q(t))

def pre.split(+m: String, pq: String & String, +headers: Map<&2, List<&2, String>>, body: Bytes.Bytes, +prefix: String) -> Pre:
  (path, query) = pq
  pre.go(P.classify(m, path, query, headers, prefix), headers, body, ct_of(headers))

def pre(req: Http.Req, +prefix: String) -> Pre:
  Http.Req{+method, +rawpath, +headers, body} = req
  pre.split(method, split_q(rawpath), headers, body, prefix)

# --- running the handler

def timed.fin(m: Maybe<&1, Reply>) -> Reply:
  match m:
    case None{}:
      fail(Code.DeadlineExceeded{}, "deadline exceeded")
    case Some{r}:
      r

# NOTE: IO.within does not cancel the loser; a handler that overruns keeps running unobserved.
def timed(~handle: Call -> IO(Reply), call: Call, t: Maybe<&2, U32>) -> IO(Reply):
  match t:
    case None{}:
      handle(call)
    case Some{+ms}:
      do IO<Reply>:
        m : Maybe<&1, Reply> <- IO.within(Reply, ms, handle(call))
        return timed.fin(m)

# --- rendering a Reply into a response head (+ body or streaming state)

def ct_hdr(m: Map<&2, List<&2, String>>, ct: String) -> Map<&2, List<&2, String>>:
  Http.set(m, "content-type", ct)

def all_hdrs(meta: Meta, ct: String) -> Map<&2, List<&2, String>>:
  Meta{hs, ts} = meta
  ct_hdr(merge(hs, Md.trailers_to_headers(ts)), ct)

def unary_ok(codec: P.Codec, b: Bytes.Bytes, meta: Meta) -> IO(Http.WriteHead<Job>):
  head(200, all_hdrs(meta, P.unary_content_type(codec)), b)

def unary_err(e: E.Error, meta: Meta) -> IO(Http.WriteHead<Job>):
  E.Error{+code, +message, details} = e
  head(Code.to_http(code), all_hdrs(meta, "application/json"), E.encode(E.Error{code, message, details}))

def single_unary(codec: P.Codec, r: Result<&1, &1, E.Error, Bytes.Bytes>, meta: Meta) -> IO(Http.WriteHead<Job>):
  match r:
    case Done{b}:
      unary_ok(codec, b, meta)
    case Fail{e}:
      unary_err(e, meta)

def stream_single.go(r: Result<&1, &1, E.Error, Bytes.Bytes>, ct: String, hs: Map<&2, List<&2, String>>, ts: Map<&2, List<&2, String>>) -> IO(Http.WriteHead<Job>):
  match r:
    case Done{b}:
      head(200, ct_hdr(hs, ct), Bytes.concat(Env.encode(Env.Envelope{0, b}) <> end_env(None{}, ts) <> Nil{}))
    case Fail{e}:
      head(200, ct_hdr(hs, ct), end_env(Some{e}, ts))

def stream_single(codec: P.Codec, r: Result<&1, &1, E.Error, Bytes.Bytes>, meta: Meta) -> IO(Http.WriteHead<Job>):
  Meta{+hs, +ts} = meta
  stream_single.go(r, P.stream_content_type(codec), hs, ts)

def many_head(codec: P.Codec, run: Sink -> IO(Sink & Result<&1, &1, E.Error, Unit>), meta: Meta) -> IO(Http.WriteHead<Job>):
  Meta{hs, ts} = meta
  IO.pure(Http.WriteHead<Job>, Http.WriteHead{200, ct_hdr(hs, P.stream_content_type(codec)), None{}, JMany{run, ts}, Completion.Unobserved{}})

def not_found() -> IO(Http.WriteHead<Job>):
  head(404, json_hdr(), E.encode(E.new(Code.NotFound{}, "no such procedure")))

def internal(msg: String) -> IO(Http.WriteHead<Job>):
  head(500, json_hdr(), E.encode(E.new(Code.Internal{}, msg)))

def render.unary(codec: P.Codec, reply: Reply) -> IO(Http.WriteHead<Job>):
  match reply:
    case Single{r, meta}:
      single_unary(codec, r, meta)
    case Many{run, meta}:
      internal("server-streaming reply returned for a unary call")
    case NoRoute{}:
      not_found()

def render.stream(codec: P.Codec, reply: Reply) -> IO(Http.WriteHead<Job>):
  match reply:
    case Single{r, meta}:
      stream_single(codec, r, meta)
    case Many{run, meta}:
      many_head(codec, run, meta)
    case NoRoute{}:
      not_found()

def render(stream: Bool, codec: P.Codec, reply: Reply) -> IO(Http.WriteHead<Job>):
  match stream:
    case True{}:
      render.stream(codec, reply)
    case False{}:
      render.unary(codec, reply)

def start2(~handle: Call -> IO(Reply), p: Pre) -> IO(Http.WriteHead<Job>):
  match p:
    case PEarly{status, headers, body}:
      head(status, headers, body)
    case PReady{call, timeout, stream, codec}:
      do IO<Http.WriteHead<Job>>:
        reply : Reply <- timed(~handle, call, timeout)
        render(stream, codec, reply)

def start(~handle: Call -> IO(Reply), ~prefix: String, req: Http.Req) -> IO(Http.WriteHead<Job>):
  start2(~handle, pre(req, prefix))

def many.end(r: Sink & Result<&1, &1, E.Error, Unit>, trailers: Map<&2, List<&2, String>>, receipt: Completion.Receipt) -> IO(Http.Writer & Completion.Receipt):
  (s, res) = r
  Sink{w} = s
  do IO<Http.Writer & Completion.Receipt>:
    w2 : Http.Writer <- Http.writer.write(w, end_bytes(res, trailers))
    return (w2, receipt)

def write(st: Job, w: Http.Writer, receipt: Completion.Receipt) -> IO(Http.Writer & Completion.Receipt):
  match st:
    case JBytes{b}:
      do IO<Http.Writer & Completion.Receipt>:
        w2 : Http.Writer <- Http.writer.write(w, b)
        return (w2, receipt)
    case JMany{run, trailers}:
      do IO<Http.Writer & Completion.Receipt>:
        r : Sink & Result<&1, &1, E.Error, Unit> <- run(Sink{w})
        many.end(r, trailers, receipt)

def dispose(st: Job) -> IO(Unit):
  match st:
    case JBytes{b}:
      IO.pure(Unit, Unit{})
    case JMany{run, trailers}:
      IO.pure(Unit, Unit{})

# Serves forever on host:port. `prefix` is "" or e.g. "/api". It is a template argument
# (pass a string literal) because serve.write.on.with takes closed templates.
def serve(~handle: Call -> IO(Reply), ~prefix: String, host: String, +port: U32) -> IO(Unit):
  Http.serve.write.on.with(~Job, ~(req => start(~handle, ~prefix, req)), ~write, ~dispose, ~Completion.ignore, host, port, 33554432n)
