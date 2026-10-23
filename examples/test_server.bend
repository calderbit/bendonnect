# bendonette.test.v1.TestService for the Go interop harness (tests/interop). Port 8787.
# Messages are google.protobuf.StringValue / UInt32Value, hand-encoded (JSON = bare value,
# proto = field 1).   Run: bend examples/test_server.bend
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-json@0.6.1.1/json.bend as Json
import bend-kit-http@0.36.0.0/http.bend as Http
import ../src/code.bend as Code
import ../src/error.bend as E
import ../src/protocol.bend as P
import ../src/transport/server.bend as Srv

def svc() -> String:
  "bendonette.test.v1.TestService/"

def ch(c: U32) -> String:
  SCon{Chr{c}, SNil{}}

def bad(msg: String) -> E.Error:
  E.new(Code.InvalidArgument{}, msg)

# ---------------------------------------------------------------- varint

def varint.more(last: Bool, +n: U32, rest: Unit -> String) -> String:
  match last:
    case True{}:
      ch(n)
    case False{}:
      ch(U32.or(U32.and(n, 127), 128)) ++ rest(Unit{})

def varint(fuel: Nat, +n: U32) -> String:
  match fuel:
    case 0n:
      ""
    case 1n+p:
      varint.more(U32.is_lt(n, 128), n, u => varint(p, U32.shrn(n, 7n)))

type Vr is Data:
  VrOk{n: U32, rest: String}
  VrBad{}

def vr.step(last: Bool, +low: U32, rest: String, +acc: U32, +sh: Nat, more: Unit -> Vr) -> Vr:
  match last:
    case True{}:
      VrOk{U32.or(acc, U32.shln(low, sh)), rest}
    case False{}:
      more(Unit{})

def vr(fuel: Nat, s: String, +acc: U32, +sh: Nat) -> Vr:
  match fuel:
    case 0n:
      VrBad{}
    case 1n+p:
      match s:
        case SNil{}:
          VrBad{}
        case SCon{Chr{+c}, +rest}:
          vr.step(U32.is_lt(c, 128), U32.and(c, 127), rest, acc, sh,
            u => vr(p, rest, U32.or(acc, U32.shln(U32.and(c, 127), sh)), Nat.add(sh, 7n)))

# ---------------------------------------------------------------- StringValue / UInt32Value

def pb.str(b: Bytes.Bytes) -> Bytes.Bytes:
  +s = Bytes.to_string(b)
  +n = U32.from_nat(String.length(s))
  Bytes.from_string(Bool.pick(String, U32.is_eq(n, 0), "", ch(10) ++ varint(5n, n) ++ s))

def pb.str.len(v: Vr) -> Result<&1, &1, E.Error, Bytes.Bytes>:
  match v:
    case VrBad{}:
      Fail{bad("bad varint in StringValue")}
    case VrOk{+n, +rest}:
      Done{Bytes.from_string(String.take(rest, U32.to_nat(n)))}

def pb.str.tag(ok: Bool, rest: String) -> Result<&1, &1, E.Error, Bytes.Bytes>:
  match ok:
    case False{}:
      Fail{bad("expected StringValue field 1")}
    case True{}:
      pb.str.len(vr(5n, rest, 0, 0n))

def pb.str.dec(s: String) -> Result<&1, &1, E.Error, Bytes.Bytes>:
  match s:
    case SNil{}:
      Done{Bytes.new(0)}
    case SCon{Chr{+c}, rest}:
      pb.str.tag(U32.is_eq(c, 10), rest)

def pb.u32.len(v: Vr) -> Result<&1, &1, E.Error, U32>:
  match v:
    case VrBad{}:
      Fail{bad("bad varint in UInt32Value")}
    case VrOk{+n, +rest}:
      Done{n}

def pb.u32.tag(ok: Bool, rest: String) -> Result<&1, &1, E.Error, U32>:
  match ok:
    case False{}:
      Fail{bad("expected UInt32Value field 1")}
    case True{}:
      pb.u32.len(vr(5n, rest, 0, 0n))

def pb.u32.dec(s: String) -> Result<&1, &1, E.Error, U32>:
  match s:
    case SNil{}:
      Done{0}
    case SCon{Chr{+c}, rest}:
      pb.u32.tag(U32.is_eq(c, 8), rest)

def js.str(m: Maybe<&1, Json.Val>) -> Result<&1, &1, E.Error, Bytes.Bytes>:
  match m:
    case Some{Json.Str{s}}:
      Done{s}
    case _:
      Fail{bad("expected a JSON string")}

def js.u32.read(m: Maybe<&2, U32>) -> Result<&1, &1, E.Error, U32>:
  match m:
    case Some{n}:
      Done{n}
    case None{}:
      Fail{bad("bad uint32")}

def js.u32(m: Maybe<&1, Json.Val>) -> Result<&1, &1, E.Error, U32>:
  match m:
    case Some{Json.Num{s}}:
      js.u32.read(U32.read(Bytes.to_string(s)))
    case _:
      Fail{bad("expected a JSON number")}

def sv.dec(codec: P.Codec, b: Bytes.Bytes) -> Result<&1, &1, E.Error, Bytes.Bytes>:
  match codec:
    case P.Json{}:
      js.str(Json.parse.bytes(b))
    case P.Proto{}:
      pb.str.dec(Bytes.to_string(b))
    case P.Custom{n}:
      Fail{E.new(Code.Unimplemented{}, "unsupported codec")}

def u32.dec(codec: P.Codec, b: Bytes.Bytes) -> Result<&1, &1, E.Error, U32>:
  match codec:
    case P.Json{}:
      js.u32(Json.parse.bytes(b))
    case P.Proto{}:
      pb.u32.dec(Bytes.to_string(b))
    case P.Custom{n}:
      Fail{E.new(Code.Unimplemented{}, "unsupported codec")}

def sv.enc(codec: P.Codec, b: Bytes.Bytes) -> Bytes.Bytes:
  match codec:
    case P.Json{}:
      Json.encode.bytes(Json.Str{b})
    case P.Proto{}:
      pb.str(b)
    case P.Custom{n}:
      Bytes.new(0)

# ---------------------------------------------------------------- helpers

def first(ms: List<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match ms:
    case Nil{}:
      Bytes.new(0)
    case Con{h, t}:
      h

def hmap(k: String, v: String) -> Map<&2, List<&2, String>>:
  Http.set(Http.empty(), k, v)

def err.reply(e: E.Error) -> Srv.Reply:
  Srv.Single{Fail{e}, Srv.meta.empty()}

# ---------------------------------------------------------------- Echo

def echo.hdrs(+h: String) -> Map<&2, List<&2, String>>:
  Bool.pick(Map<&2, List<&2, String>>, String.is_empty(h), Http.empty(), hmap("x-echo", h))

def echo.done(codec: P.Codec, h: String, r: Result<&1, &1, E.Error, Bytes.Bytes>) -> Srv.Reply:
  match r:
    case Fail{e}:
      err.reply(e)
    case Done{b}:
      Srv.Single{Done{sv.enc(codec, b)}, Srv.Meta{echo.hdrs(h), hmap("x-trail", "done")}}

def echo(+codec: P.Codec, +headers: Map<&2, List<&2, String>>, ms: List<&1, Bytes.Bytes>) -> Srv.Reply:
  echo.done(codec, Http.header(headers, "x-test"), sv.dec(codec, first(ms)))

# ---------------------------------------------------------------- Fail

def fail.detail() -> E.Detail:
  E.Detail{"google.protobuf.StringValue", pb.str(Bytes.from_string("detail")), None{}}

def fail.code(m: Maybe<&2, Code.Code>) -> Srv.Reply:
  match m:
    case None{}:
      err.reply(bad("bad code name"))
    case Some{c}:
      err.reply(E.Error{c, "requested failure", fail.detail() <> Nil{}})

def fail.done(r: Result<&1, &1, E.Error, Bytes.Bytes>) -> Srv.Reply:
  match r:
    case Fail{e}:
      err.reply(e)
    case Done{b}:
      fail.code(Code.from_string(Bytes.to_string(b)))

def fail(codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> Srv.Reply:
  fail.done(sv.dec(codec, first(ms)))

# ---------------------------------------------------------------- Count (server stream)

def count.loop(+codec: P.Codec, fuel: Nat, +i: U32, sink: Srv.Sink) -> IO(Srv.Sink & Result<&1, &1, E.Error, Unit>):
  match fuel:
    case 0n:
      IO.pure(Srv.Sink & Result<&1, &1, E.Error, Unit>, (sink, Done{Unit{}}))
    case 1n+p:
      do IO<Srv.Sink & Result<&1, &1, E.Error, Unit>>:
        s2 : Srv.Sink <- Srv.send(sink, sv.enc(codec, Bytes.from_string(U32.show(i))))
        count.loop(codec, p, (i + 1 : U32), s2)

def count.go(zero: Bool, +codec: P.Codec, +n: U32) -> Srv.Reply:
  match zero:
    case True{}:
      Srv.Single{Fail{E.new(Code.OutOfRange{}, "n must be > 0")}, Srv.Meta{Http.empty(), hmap("x-count", "0")}}
    case False{}:
      Srv.Many{sink => count.loop(codec, U32.to_nat(n), 1, sink), Srv.Meta{Http.empty(), hmap("x-count", U32.show(n))}}

def count.n(+codec: P.Codec, +n: U32) -> Srv.Reply:
  count.go(U32.is_eq(n, 0), codec, n)

def count.done(codec: P.Codec, r: Result<&1, &1, E.Error, U32>) -> Srv.Reply:
  match r:
    case Fail{e}:
      err.reply(e)
    case Done{n}:
      count.n(codec, n)

def count(+codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> Srv.Reply:
  count.done(codec, u32.dec(codec, first(ms)))

# ---------------------------------------------------------------- Concat (client stream)

def cat.step(r: Result<&1, &1, E.Error, Bytes.Bytes>, +first: Bool, acc: Bytes.Bytes, more: Bytes.Bytes -> Result<&1, &1, E.Error, Bytes.Bytes>) -> Result<&1, &1, E.Error, Bytes.Bytes>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{b}:
      more(Bytes.concat(acc <> Bytes.from_string(Bool.pick(String, first, "", " ")) <> b <> Nil{}))

def cat.go(+codec: P.Codec, ms: List<&1, Bytes.Bytes>, +first: Bool, acc: Bytes.Bytes) -> Result<&1, &1, E.Error, Bytes.Bytes>:
  match ms:
    case Nil{}:
      Done{acc}
    case Con{h, t}:
      cat.step(sv.dec(codec, h), first, acc, nb => cat.go(codec, t, False{}, nb))

def cat.done(codec: P.Codec, r: Result<&1, &1, E.Error, Bytes.Bytes>) -> Srv.Reply:
  match r:
    case Fail{e}:
      err.reply(e)
    case Done{b}:
      Srv.ok(sv.enc(codec, b))

def concat(+codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> Srv.Reply:
  cat.done(codec, cat.go(codec, ms, True{}, Bytes.new(0)))

# ---------------------------------------------------------------- routing

def route3(is_cat: Bool, codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> Srv.Reply:
  match is_cat:
    case True{}:
      concat(codec, ms)
    case False{}:
      Srv.NoRoute{}

def route2(is_count: Bool, is_cat: Bool, codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> Srv.Reply:
  match is_count:
    case True{}:
      count(codec, ms)
    case False{}:
      route3(is_cat, codec, ms)

def route1(is_fail: Bool, is_count: Bool, is_cat: Bool, codec: P.Codec, ms: List<&1, Bytes.Bytes>) -> Srv.Reply:
  match is_fail:
    case True{}:
      fail(codec, ms)
    case False{}:
      route2(is_count, is_cat, codec, ms)

def route(is_echo: Bool, is_fail: Bool, is_count: Bool, is_cat: Bool, codec: P.Codec, headers: Map<&2, List<&2, String>>, ms: List<&1, Bytes.Bytes>) -> Srv.Reply:
  match is_echo:
    case True{}:
      echo(codec, headers, ms)
    case False{}:
      route1(is_fail, is_count, is_cat, codec, ms)

def handle(call: Srv.Call) -> IO(Srv.Reply):
  Srv.Call{+procedure, kind, codec, headers, timeout_ms, messages} = call
  IO.pure(Srv.Reply, route(String.eq(procedure, svc() ++ "Echo"), String.eq(procedure, svc() ++ "Fail"),
    String.eq(procedure, svc() ++ "Count"), String.eq(procedure, svc() ++ "Concat"), codec, headers, messages))

def main() -> IO(Unit):
  Srv.serve(~handle, ~"", "127.0.0.1", 8787)
