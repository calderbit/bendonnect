# Calls examples/greet_server.bend (run it first): JSON unary, then a server stream.
#   bend examples/greet_client.bend
import Base
import bend-kit-http@0.36.0.0/http.bend as Http
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ../src/code.bend as Code
import ../src/error.bend as E
import ../src/protocol.bend as P
import ../src/transport/client.bend as Cli

def base() -> String:
  "http://127.0.0.1:8787"

def request() -> Bytes.Bytes:
  Bytes.from_string("{\"name\":\"Ada\"}")

def show_msg(m: Bytes.Bytes) -> IO(Unit):
  IO.print("  " ++ Bytes.to_string(m))

def show_all(ms: List<&1, Bytes.Bytes>) -> IO(Unit):
  match ms:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      do IO<Unit>:
        show_msg(h)
        show_all(t)

def show_err(e: E.Error) -> IO(Unit):
  E.Error{code, message, details} = e
  IO.print("error " ++ Code.to_string(code) ++ ": " ++ message)

def show(r: Result<&1, &1, E.Error, Cli.Response>) -> IO(Unit):
  match r:
    case Fail{e}:
      show_err(e)
    case Done{resp}:
      Cli.Response{h, t, ms} = resp
      show_all(ms)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("Greet:")
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.unary(base(), "greet.v1.GreetService/Greet", P.Json{}, Http.empty(), request())
    show(r)
    IO.print("GreetMany (printed as each message arrives):")
    s : Result<&1, &1, E.Error, Cli.Response> <- Cli.server_stream.each(~show_msg, base(), "greet.v1.GreetService/GreetMany", P.Json{}, Http.empty(), request())
    show(s)
