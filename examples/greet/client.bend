# Calls server.bend (run it first) through the generated client functions, proto codec.
#   bend examples/greet/client.bend
import Base
import bend-kit-http@0.36.0.0/http.bend as Http
import ../../src/code.bend as Code
import ../../src/error.bend as E
import ../../src/protocol.bend as P
import ./greet_pb.bend as G
import ./greet_connect.bend as C

def base() -> String:
  "http://127.0.0.1:8787"

def show_err(e: E.Error) -> IO(Unit):
  E.Error{code, message, details} = e
  IO.print("error " ++ Code.to_string(code) ++ ": " ++ message)

def show_one(r: Result<&1, &1, E.Error, G.GreetResponse>) -> IO(Unit):
  match r:
    case Fail{e}:
      show_err(e)
    case Done{G.GreetResponse{greeting}}:
      IO.print("  " ++ greeting)

def show_greetings(rs: List<&2, G.GreetResponse>) -> IO(Unit):
  match rs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{G.GreetResponse{greeting}, rest}:
      do IO<Unit>:
        IO.print("  " ++ greeting)
        show_greetings(rest)

def show_many(r: Result<&1, &1, E.Error, List<&2, G.GreetResponse>>) -> IO(Unit):
  match r:
    case Fail{e}:
      show_err(e)
    case Done{rs}:
      show_greetings(rs)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("Greet:")
    one : Result<&1, &1, E.Error, G.GreetResponse> <- C.GreetService.greet(base(), P.Proto{}, Http.empty(), G.GreetRequest{"Ada"})
    show_one(one)
    IO.print("GreetMany:")
    many : Result<&1, &1, E.Error, List<&2, G.GreetResponse>> <- C.GreetService.greet_many(base(), P.Proto{}, Http.empty(), G.GreetRequest{"Grace"})
    show_many(many)
    IO.print("GreetAll:")
    all : Result<&1, &1, E.Error, G.GreetResponse> <- C.GreetService.greet_all(base(), P.Proto{}, Http.empty(), [G.GreetRequest{"Ada"}, G.GreetRequest{"Grace"}])
    show_one(all)
    IO.print("Greet (GET, json):")
    got : Result<&1, &1, E.Error, G.GreetResponse> <- C.GreetService.greet_get(base(), P.Json{}, Http.empty(), G.GreetRequest{"Edsger"})
    show_one(got)
