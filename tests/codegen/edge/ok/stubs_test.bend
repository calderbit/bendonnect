# Instantiates the generated Eval service (all four method kinds) so the templates typecheck.
# Compiled to C only (see tests/codegen/run.sh); it is never run.
import Base
import ../../../../src/error.bend as E
import ../../../../src/protocol.bend as P
import ../../../../src/transport/rpc.bend as Rpc
import ../../../../src/transport/server.bend as Srv
import ./gen/app/app_pb.bend as A
import ./gen/app/app_connect.bend as C

def run(ctx: Rpc.Ctx, req: A.Expr) -> IO(Result<&1, &1, E.Error, A.Event_>):
  IO.pure(Result<&1, &1, E.Error, A.Event_>, Done{A.Event_.default()})

def watch(ctx: Rpc.Ctx, req: A.Empty_, out: Rpc.Out) -> IO(Rpc.Out & Result<&1, &1, E.Error, Unit>):
  do IO<Rpc.Out & Result<&1, &1, E.Error, Unit>>:
    out2 : Rpc.Out <- C.Eval.Watch.send(out, A.Event_.default())
    return (out2, Done{Unit{}})

def push(ctx: Rpc.Ctx, reqs: List<&2, A.Expr>) -> IO(Result<&1, &1, E.Error, A.Event_>):
  IO.pure(Result<&1, &1, E.Error, A.Event_>, Done{A.Event_.default()})

def handle(call: Srv.Call) -> IO(Srv.Reply):
  C.Eval.handle(~run, ~watch, ~push, call)

def client(base: String) -> IO(Result<&1, &1, E.Error, A.Event_>):
  C.Eval.run(base, P.Json{}, Map.new(&2, List<&2, String>), A.Expr.default())

def main() -> IO(Unit):
  IO.pure(Unit, Unit{})
