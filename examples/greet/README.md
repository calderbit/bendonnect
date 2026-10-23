# greet: protoc-gen-bend end to end

`proto/greet.proto` (package `greet.v1`) has a unary method marked `NO_SIDE_EFFECTS`, a server
stream and a client stream. `buf generate` produces:

| file | what |
|------|------|
| `greet_pb.bend` | messages, proto binary and proto3 JSON codecs (pure: `bend greet_pb.bend` prints ALL PROOFS CHECK) |
| `greet_connect.bend` | server handler and client functions on the Bendonnect transport |
| `goclient/greetv1/**` | protoc-gen-go and protoc-gen-connect-go output, used by the Go test client |

The whole server is `server.bend`:

```python
def hello(+name: String) -> G.GreetResponse:
  G.GreetResponse{"Hello, " ++ name ++ "!"}

def greet(ctx: Rpc.Ctx, req: G.GreetRequest) -> IO(Result<&1, &1, E.Error, G.GreetResponse>):
  G.GreetRequest{name} = req
  IO.pure(Result<&1, &1, E.Error, G.GreetResponse>, Done{hello(name)})

def handle(call: Srv.Call) -> IO(Srv.Reply):
  C.GreetService.handle(~greet, ~greet_many, ~greet_all, call)

def main() -> IO(Unit):
  Srv.serve(~handle, ~"", "127.0.0.1", 8787)
```

and `client.bend` calls it with `C.GreetService.greet(base, P.Proto{}, headers, req)` (also
`greet_many`, `greet_all`, and `greet_get` for the `NO_SIDE_EFFECTS` method).

## Run

    bend examples/greet/server.bend            # serves on 127.0.0.1:8787
    bend examples/greet/client.bend            # in another shell
    examples/greet/run_e2e.sh                  # regenerates, serves, runs the connect-go client
                                               # (proto + json, POST + GET, all three method kinds)
                                               # and the Bend client; kills only its own server

Regenerate by hand from this directory: `buf generate` (needs `protoc-gen-go` and
`protoc-gen-connect-go` on PATH and the plugin built with
`cd ../../cmd/protoc-gen-bend && go build -o bin/protoc-gen-bend .`; `run_e2e.sh` does all that).
