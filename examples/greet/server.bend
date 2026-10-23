# GreetService (greet.proto) served with the generated handler.
#   bend examples/greet/server.bend
#   curl -s localhost:8787/greet.v1.GreetService/Greet -H 'Content-Type: application/json' -d '{"name":"Ada"}'
#   -> {"greeting":"Hello, Ada!"}
import Base
import ../../src/error.bend as E
import ../../src/transport/rpc.bend as Rpc
import ../../src/transport/server.bend as Srv
import ./greet_pb.bend as G
import ./greet_connect.bend as C

def hello(+name: String) -> G.GreetResponse:
  G.GreetResponse{"Hello, " ++ name ++ "!"}

# Unary: one request, one response.
def greet(ctx: Rpc.Ctx, req: G.GreetRequest) -> IO(Result<&1, &1, E.Error, G.GreetResponse>):
  G.GreetRequest{name} = req
  IO.pure(Result<&1, &1, E.Error, G.GreetResponse>, Done{hello(name)})

# Server stream: three greetings, each flushed as soon as it is sent.
def greet_many(ctx: Rpc.Ctx, req: G.GreetRequest, out: Rpc.Out) -> IO(Rpc.Out & Result<&1, &1, E.Error, Unit>):
  G.GreetRequest{+name} = req
  do IO<Rpc.Out & Result<&1, &1, E.Error, Unit>>:
    out1 : Rpc.Out <- C.GreetService.GreetMany.send(out, hello(name ++ " (1)"))
    out2 : Rpc.Out <- C.GreetService.GreetMany.send(out1, hello(name ++ " (2)"))
    out3 : Rpc.Out <- C.GreetService.GreetMany.send(out2, hello(name ++ " (3)"))
    return (out3, Done{Unit{}})

def names(reqs: List<&2, G.GreetRequest>) -> List<&2, String>:
  match reqs:
    case Nil{}:
      Nil{}
    case Con{G.GreetRequest{name}, rest}:
      Con{name, names(rest)}

# Client stream: every name in, one greeting for all out.
def greet_all(ctx: Rpc.Ctx, reqs: List<&2, G.GreetRequest>) -> IO(Result<&1, &1, E.Error, G.GreetResponse>):
  IO.pure(Result<&1, &1, E.Error, G.GreetResponse>, Done{hello(String.join(names(reqs), ", "))})

def handle(call: Srv.Call) -> IO(Srv.Reply):
  C.GreetService.handle(~greet, ~greet_many, ~greet_all, call)

def main() -> IO(Unit):
  Srv.serve(~handle, ~"", "127.0.0.1", 8787)
