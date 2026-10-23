# Typed RPC adapters between generated code and the byte-level transports (Srv, Cli).
# Reference: docs/runtime.md. Templates come first in every parameter list; the codec functions
# are the generated `Msg.decode(+codec, b)` / `Msg.encode(+codec, m)`, hence the `@+codec` arrows.
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ../code.bend as Code
import ../error.bend as E
import ../protocol.bend as P
import ./server.bend as Srv
import ./client.bend as Cli

# ------------------------------------------------------------------ types

# What a handler learns about the call it serves.
type Ctx is Data:
  Ctx{procedure: String, codec: P.Codec, headers: Map<&2, List<&2, String>>}

# A typed server-stream sender: pass it through Rpc.send / the generated per-method send.
type Out is Type:
  Out{sink: Srv.Sink, codec: P.Codec}

# ------------------------------------------------------------------ small helpers

def err_reply(e: E.Error) -> Srv.Reply:
  Srv.Single{Fail{e}, Srv.meta.empty()}

def bad_request(+message: String) -> Srv.Reply:
  Srv.fail(Code.InvalidArgument{}, message)

def reply_io(r: Srv.Reply) -> IO(Srv.Reply):
  IO.pure(Srv.Reply, r)

def no_custom(+name: String) -> Srv.Reply:
  Srv.fail(Code.Unimplemented{}, String.append("codec not supported: ", name))

# Unknown procedure: the server answers 404.
def no_route(call: Srv.Call) -> IO(Srv.Reply):
  reply_io(Srv.NoRoute{})

# Bidirectional streaming is not supported by the HTTP/1.1 transport.
def bidi_unimplemented(call: Srv.Call) -> IO(Srv.Reply):
  reply_io(Srv.fail(Code.Unimplemented{}, "bidirectional streaming is not supported"))

def route.pick(~hit: Srv.Call -> IO(Srv.Reply), ~miss: Srv.Call -> IO(Srv.Reply), b: Bool, call: Srv.Call) -> IO(Srv.Reply):
  match b:
    case True{}:
      hit(call)
    case False{}:
      miss(call)

# if call.procedure == procedure then hit(call) else miss(call); chain these, ending in no_route.
def route(~hit: Srv.Call -> IO(Srv.Reply), ~miss: Srv.Call -> IO(Srv.Reply), +procedure: String, call: Srv.Call) -> IO(Srv.Reply):
  Srv.Call{+p, kind, codec, headers, timeout_ms, messages} = call
  route.pick(~hit, ~miss, String.eq(p, procedure), Srv.Call{p, kind, codec, headers, timeout_ms, messages})

# ------------------------------------------------------------------ server: unary

def enc_res(~Res: Data, ~enc: @+codec: P.Codec -> Res -> Bytes.Bytes, +codec: P.Codec, r: Result<&1, &1, E.Error, Res>) -> Result<&1, &1, E.Error, Bytes.Bytes>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{x}:
      Done{enc(codec, x)}

def unary.reply(~Res: Data, ~enc: @+codec: P.Codec -> Res -> Bytes.Bytes, +codec: P.Codec, r: Result<&1, &1, E.Error, Res>) -> Srv.Reply:
  Srv.Single{enc_res(~Res, ~enc, codec, r), Srv.meta.empty()}

def unary.run(~Req: Data, ~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Req>, ~enc: @+codec: P.Codec -> Res -> Bytes.Bytes, ~impl: Ctx -> Req -> IO(Result<&1, &1, E.Error, Res>), ctx: Ctx, +codec: P.Codec, r: Result<&1, &1, E.Error, Req>) -> IO(Srv.Reply):
  match r:
    case Fail{e}:
      reply_io(err_reply(e))
    case Done{req}:
      do IO<Srv.Reply>:
        res : Result<&1, &1, E.Error, Res> <- impl(ctx, req)
        return unary.reply(~Res, ~enc, codec, res)

def unary.one(~Req: Data, ~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Req>, ~enc: @+codec: P.Codec -> Res -> Bytes.Bytes, ~impl: Ctx -> Req -> IO(Result<&1, &1, E.Error, Res>), ctx: Ctx, +codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> IO(Srv.Reply):
  match ms:
    case Nil{}:
      reply_io(bad_request("expected exactly one request message"))
    case Con{m, rest}:
      match rest:
        case Nil{}:
          unary.run(~Req, ~Res, ~dec, ~enc, ~impl, ctx, codec, dec(codec, m))
        case Con{x, y}:
          reply_io(bad_request("expected exactly one request message"))

# Serves a unary method: decode the single request message, run impl, encode the response.
# A decode error (already an E.Error from the generated decoder) is returned as is.
def unary(~Req: Data, ~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Req>, ~enc: @+codec: P.Codec -> Res -> Bytes.Bytes, ~impl: Ctx -> Req -> IO(Result<&1, &1, E.Error, Res>), call: Srv.Call) -> IO(Srv.Reply):
  Srv.Call{procedure, kind, +codec, headers, timeout_ms, messages} = call
  match codec:
    case P.Custom{name}:
      reply_io(no_custom(name))
    case P.Json{}:
      unary.one(~Req, ~Res, ~dec, ~enc, ~impl, Ctx{procedure, P.Json{}, headers}, P.Json{}, messages)
    case P.Proto{}:
      unary.one(~Req, ~Res, ~dec, ~enc, ~impl, Ctx{procedure, P.Proto{}, headers}, P.Proto{}, messages)

# ------------------------------------------------------------------ server: server stream

# Sends one typed message on a server stream.
def send.go(~T: Data, ~enc: @+codec: P.Codec -> T -> Bytes.Bytes, sink2: IO(Srv.Sink), codec: P.Codec) -> IO(Out):
  do IO<Out>:
    s : Srv.Sink <- sink2
    return Out{s, codec}

def send(~T: Data, ~enc: @+codec: P.Codec -> T -> Bytes.Bytes, out: Out, msg: T) -> IO(Out):
  Out{sink, +codec} = out
  send.go(~T, ~enc, Srv.send(sink, enc(codec, msg)), codec)

def ss.fin(r: Out & Result<&1, &1, E.Error, Unit>) -> Srv.Sink & Result<&1, &1, E.Error, Unit>:
  (out, res) = r
  Out{sink, codec} = out
  (sink, res)

def ss.exec(~Req: Data, ~impl: Ctx -> Req -> Out -> IO(Out & Result<&1, &1, E.Error, Unit>), procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, req: Req, sink: Srv.Sink) -> IO(Srv.Sink & Result<&1, &1, E.Error, Unit>):
  do IO<Srv.Sink & Result<&1, &1, E.Error, Unit>>:
    r : Out & Result<&1, &1, E.Error, Unit> <- impl(Ctx{procedure, codec, headers}, req, Out{sink, codec})
    return ss.fin(r)

def ss.reply(~Req: Data, ~impl: Ctx -> Req -> Out -> IO(Out & Result<&1, &1, E.Error, Unit>), procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, r: Result<&1, &1, E.Error, Req>) -> IO(Srv.Reply):
  match r:
    case Fail{e}:
      reply_io(err_reply(e))
    case Done{req}:
      reply_io(Srv.Many{sink => ss.exec(~Req, ~impl, procedure, codec, headers, req, sink), Srv.meta.empty()})

def ss.one(~Req: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Req>, ~impl: Ctx -> Req -> Out -> IO(Out & Result<&1, &1, E.Error, Unit>), procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, ms: List<&1, Bytes.Bytes>) -> IO(Srv.Reply):
  match ms:
    case Nil{}:
      reply_io(bad_request("expected exactly one request message"))
    case Con{m, rest}:
      match rest:
        case Nil{}:
          ss.reply(~Req, ~impl, procedure, codec, headers, dec(codec, m))
        case Con{x, y}:
          reply_io(bad_request("expected exactly one request message"))

# Serves a server-streaming method: impl gets the request and an Out to Rpc.send on, and returns
# the final Out with Done (stream ends cleanly) or Fail (error in the EndStream message).
def server_stream(~Req: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Req>, ~impl: Ctx -> Req -> Out -> IO(Out & Result<&1, &1, E.Error, Unit>), call: Srv.Call) -> IO(Srv.Reply):
  Srv.Call{procedure, kind, +codec, headers, timeout_ms, messages} = call
  match codec:
    case P.Custom{name}:
      reply_io(no_custom(name))
    case P.Json{}:
      ss.one(~Req, ~dec, ~impl, procedure, P.Json{}, headers, messages)
    case P.Proto{}:
      ss.one(~Req, ~dec, ~impl, procedure, P.Proto{}, headers, messages)

# ------------------------------------------------------------------ server: client stream

def dec_all(~Req: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Req>, +codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> Result<&1, &1, E.Error, List<&2, Req>>:
  match ms:
    case Nil{}:
      Done{Nil{}}
    case Con{m, t}:
      do Result<&1, &1, E.Error, List<&2, Req>>:
        x : Req <- dec(codec, m)
        rest : List<&2, Req> <- dec_all(~Req, ~dec, codec, t)
        return x <> rest

def cs.run(~Req: Data, ~Res: Data, ~enc: @+codec: P.Codec -> Res -> Bytes.Bytes, ~impl: Ctx -> List<&2, Req> -> IO(Result<&1, &1, E.Error, Res>), ctx: Ctx, +codec: P.Codec, r: Result<&1, &1, E.Error, List<&2, Req>>) -> IO(Srv.Reply):
  match r:
    case Fail{e}:
      reply_io(err_reply(e))
    case Done{reqs}:
      do IO<Srv.Reply>:
        res : Result<&1, &1, E.Error, Res> <- impl(ctx, reqs)
        return unary.reply(~Res, ~enc, codec, res)

# Serves a client-streaming method: all request messages are decoded first (the transport buffers
# them), impl answers with the single response.
def client_stream(~Req: Data, ~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Req>, ~enc: @+codec: P.Codec -> Res -> Bytes.Bytes, ~impl: Ctx -> List<&2, Req> -> IO(Result<&1, &1, E.Error, Res>), call: Srv.Call) -> IO(Srv.Reply):
  Srv.Call{procedure, kind, +codec, headers, timeout_ms, messages} = call
  match codec:
    case P.Custom{name}:
      reply_io(no_custom(name))
    case P.Json{}:
      cs.run(~Req, ~Res, ~enc, ~impl, Ctx{procedure, P.Json{}, headers}, P.Json{}, dec_all(~Req, ~dec, P.Json{}, messages))
    case P.Proto{}:
      cs.run(~Req, ~Res, ~enc, ~impl, Ctx{procedure, P.Proto{}, headers}, P.Proto{}, dec_all(~Req, ~dec, P.Proto{}, messages))

# ------------------------------------------------------------------ client

def bad_response(+message: String) -> E.Error:
  E.new(Code.Unknown{}, message)

def one_msg(~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Res>, +codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> Result<&1, &1, E.Error, Res>:
  match ms:
    case Nil{}:
      Fail{bad_response("no response message")}
    case Con{m, rest}:
      match rest:
        case Nil{}:
          dec(codec, m)
        case Con{x, y}:
          Fail{bad_response("more than one response message")}

def one_res(~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Res>, +codec: P.Codec, r: Result<&1, &1, E.Error, Cli.Response>) -> Result<&1, &1, E.Error, Res>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{Cli.Response{h, t, ms}}:
      one_msg(~Res, ~dec, codec, ms)

def dec_msgs(~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Res>, +codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> Result<&1, &1, E.Error, List<&2, Res>>:
  dec_all(~Res, ~dec, codec, ms)

def many_res(~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Res>, +codec: P.Codec, r: Result<&1, &1, E.Error, Cli.Response>) -> Result<&1, &1, E.Error, List<&2, Res>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{Cli.Response{h, t, ms}}:
      dec_msgs(~Res, ~dec, codec, ms)

def enc_all(~Req: Data, ~enc: @+codec: P.Codec -> Req -> Bytes.Bytes, +codec: P.Codec, xs: List<&2, Req>) -> List<&1, Bytes.Bytes>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      enc(codec, x) <> enc_all(~Req, ~enc, codec, t)

# Unary call. headers: request headers (lowercase keys). Errors: transport failure -> Unavailable,
# non-200 -> the server's error, undecodable response -> the decoder's error.
def call.unary(~Req: Data, ~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Res>, ~enc: @+codec: P.Codec -> Req -> Bytes.Bytes, base_url: String, procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, req: Req) -> IO(Result<&1, &1, E.Error, Res>):
  do IO<Result<&1, &1, E.Error, Res>>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.unary(base_url, procedure, codec, headers, enc(codec, req))
    return one_res(~Res, ~dec, codec, r)

# Server-streaming call; collects every message (an error end-stream turns the whole call into Fail).
def call.server_stream(~Req: Data, ~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Res>, ~enc: @+codec: P.Codec -> Req -> Bytes.Bytes, base_url: String, procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, req: Req) -> IO(Result<&1, &1, E.Error, List<&2, Res>>):
  do IO<Result<&1, &1, E.Error, List<&2, Res>>>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.server_stream(base_url, procedure, codec, headers, enc(codec, req))
    return many_res(~Res, ~dec, codec, r)

# Client-streaming call: sends all reqs, answers the single response.
def call.client_stream(~Req: Data, ~Res: Data, ~dec: @+codec: P.Codec -> Bytes.Bytes -> Result<&1, &1, E.Error, Res>, ~enc: @+codec: P.Codec -> Req -> Bytes.Bytes, base_url: String, procedure: String, +codec: P.Codec, headers: Map<&2, List<&2, String>>, reqs: List<&2, Req>) -> IO(Result<&1, &1, E.Error, Res>):
  do IO<Result<&1, &1, E.Error, Res>>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.client_stream(base_url, procedure, codec, headers, enc_all(~Req, ~enc, codec, reqs))
    return one_res(~Res, ~dec, codec, r)
