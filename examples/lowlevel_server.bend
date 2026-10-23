# A small JSON-only Connect service: unary Greet and server-streaming GreetMany.
#   bend examples/lowlevel_server.bend
#   curl -s localhost:8787/greet.v1.GreetService/Greet -H 'Content-Type: application/json' -d '{"name":"Ada"}'
#   -> {"greeting":"Hello, Ada!"}
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-encoding@0.4.0.0/encoding.bend as Enc
import bend-kit-json@0.6.1.1/json.bend as Json
import ../src/code.bend as Code
import ../src/error.bend as E
import ../src/protocol.bend as P
import ../src/transport/server.bend as Srv

# ---- JSON helpers: {"name": "..."} in, {"greeting": "..."} out

def pick(hit: Bool, v: Json.Val, rest: Unit -> String) -> String:
  match hit:
    case True{}:
      match v:
        case Json.Str{s}:
          Enc.utf8.decode(s)
        case _:
          "world"
    case False{}:
      rest(Unit{})

def find(kvs: List<&1, Bytes.Bytes & Json.Val>) -> String:
  match kvs:
    case Nil{}:
      "world"
    case Con{Tuple{k, v}, rest}:
      pick(String.eq(Enc.utf8.decode(k), "name"), v, u => find(rest))

def name_of(m: Maybe<&1, Json.Val>) -> String:
  match m:
    case Some{Json.Obj{kvs}}:
      find(kvs)
    case _:
      "world"

def greeting(+name: String, +i: U32) -> Bytes.Bytes:
  Json.encode.bytes(Json.Obj{(Enc.utf8.encode("greeting"), Json.Str{Enc.utf8.encode("Hello, " ++ name ++ "! (" ++ U32.show(i) ++ ")")}) <> Nil{}})

def first(ms: List<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match ms:
    case Nil{}:
      Bytes.new(0)
    case Con{h, t}:
      h

# ---- server stream: three greetings, each flushed as it is produced

def many(+name: String, fuel: Nat, +i: U32, sink: Srv.Sink) -> IO(Srv.Sink & Result<&1, &1, E.Error, Unit>):
  match fuel:
    case 0n:
      IO.pure(Srv.Sink & Result<&1, &1, E.Error, Unit>, (sink, Done{Unit{}}))
    case 1n+p:
      do IO<Srv.Sink & Result<&1, &1, E.Error, Unit>>:
        s2 : Srv.Sink <- Srv.send(sink, greeting(name, i))
        IO.sleep(200)
        many(name, p, (i + 1 : U32), s2)

# ---- routing

def respond(+is_greet: Bool, +is_many: Bool, +name: String) -> Srv.Reply:
  match is_greet:
    case True{}:
      Srv.ok(greeting(name, 1))
    case False{}:
      match is_many:
        case True{}:
          Srv.Many{sink => many(name, 3n, 1, sink), Srv.meta.empty()}
        case False{}:
          Srv.NoRoute{}

def handle(call: Srv.Call) -> IO(Srv.Reply):
  Srv.Call{+procedure, kind, codec, headers, timeout_ms, messages} = call
  IO.pure(Srv.Reply, respond(String.eq(procedure, "greet.v1.GreetService/Greet"),
    String.eq(procedure, "greet.v1.GreetService/GreetMany"), name_of(Json.parse.bytes(first(messages)))))

def main() -> IO(Unit):
  Srv.serve(~handle, ~"", "127.0.0.1", 8787)
