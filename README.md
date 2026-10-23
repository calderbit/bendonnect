# Bendonette

[Connect protocol](https://connectrpc.com/docs/protocol/) for [Bend 2](https://bend-lang.com):
servers, clients and a `protoc-gen-bend` code generator. A Bendonette service talks to
connect-go, connect-es, connect-swift and the other Connect clients, and to plain `curl`.

- **Unary** (POST and GET), **server streaming** and **client streaming**, over HTTP/1.1
- **JSON and binary Protobuf** codecs, with the canonical proto3 JSON mapping
- Errors with codes, messages and details; headers, trailers and `-bin` metadata; timeouts
- A **proven core**: the protocol logic is pure Bend, and `LAWS.bend` states facts about it that
  the compiler checks on every build (see [Laws](#laws))
- Tested against **connect-go** in both directions

## Quick start

```proto
// greet.proto
syntax = "proto3";
package greet.v1;

message GreetRequest  { string name = 1; }
message GreetResponse { string greeting = 1; }

service GreetService {
  rpc Greet(GreetRequest) returns (GreetResponse) {
    option idempotency_level = NO_SIDE_EFFECTS;   // also callable with HTTP GET
  }
  rpc GreetMany(GreetRequest) returns (stream GreetResponse) {}
  rpc GreetAll(stream GreetRequest) returns (GreetResponse) {}
}
```

Generate Bend code with buf (`runtime` is the path from the output directory to this repo):

```yaml
# buf.gen.yaml
version: v2
plugins:
  - local: path/to/protoc-gen-bend      # cd cmd/protoc-gen-bend && go build -o bin/protoc-gen-bend .
    out: .
    opt: [runtime=../..]
```

This writes `greet_pb.bend` (messages and both codecs) and `greet_connect.bend` (server handler
and client functions). Then implement the service:

```python
import Base
import ../../src/error.bend as E
import ../../src/transport/rpc.bend as Rpc
import ../../src/transport/server.bend as Srv
import ./greet_pb.bend as G
import ./greet_connect.bend as C

def greet(ctx: Rpc.Ctx, req: G.GreetRequest) -> IO(Result<&1, &1, E.Error, G.GreetResponse>):
  G.GreetRequest{name} = req
  IO.pure(Result<&1, &1, E.Error, G.GreetResponse>, Done{G.GreetResponse{"Hello, " ++ name ++ "!"}})

# greet_many(ctx, req, out) streams with C.GreetService.GreetMany.send(out, msg);
# greet_all(ctx, reqs) receives every streamed request. See examples/greet/server.bend.

def handle(call: Srv.Call) -> IO(Srv.Reply):
  C.GreetService.handle(~greet, ~greet_many, ~greet_all, call)

def main() -> IO(Unit):
  Srv.serve(~handle, ~"", "127.0.0.1", 8787)
```

```console
$ bend examples/greet/server.bend
$ curl localhost:8787/greet.v1.GreetService/Greet -H 'Content-Type: application/json' -d '{"name":"Ada"}'
{"greeting":"Hello, Ada!"}
$ curl 'localhost:8787/greet.v1.GreetService/Greet?connect=v1&encoding=json&message=%7B%22name%22%3A%22Ada%22%7D'
{"greeting":"Hello, Ada!"}
```

Calling it from Bend uses the generated client functions (see `examples/greet/client.bend`):

```python
# imports as above, plus: import ../../src/protocol.bend as P
#                         import bend-kit-http@0.36.0.0/http.bend as Http
r : Result<&1, &1, E.Error, G.GreetResponse> <- C.GreetService.greet("http://127.0.0.1:8787", P.Proto{}, Http.empty(), G.GreetRequest{"Ada"})
```

`bend file.bend` runs a program directly. `bend file.bend -o server` builds a native binary,
which needs clang 14+ (`zig cc` works as a stand-in).

## Layout

| Path | What |
|---|---|
| `src/code.bend` | The 16 error codes and their HTTP mappings |
| `src/error.bend` | `Error` (code, message, details) and `EndStream`, as Connect JSON |
| `src/envelope.bend` | Streaming envelopes: flags, big-endian length, incremental decoder |
| `src/protocol.bend` | Request classification: path, codec, GET query, timeout, compression, rejections |
| `src/metadata.bend`, `src/b64.bend` | Trailer prefixing, metadata keys, base64 (std and URL-safe) |
| `src/pb.bend`, `src/pbjson.bend` | Protobuf binary and proto3 JSON runtime for generated code |
| `src/transport/server.bend` | HTTP/1.1 server: `Srv.serve(~handle, ~prefix, host, port)` |
| `src/transport/client.bend` | HTTP/1.1 client: `unary`, `get`, `server_stream(.each)`, `client_stream` |
| `src/transport/rpc.bend` | Typed adapters used by generated code |
| `cmd/protoc-gen-bend/` | The code generator (Go), see its README |
| `examples/greet/` | Generated service, server, client and a connect-go client |
| `examples/lowlevel_*.bend` | The untyped API: raw bytes in, raw bytes out |
| `docs/runtime.md` | Reference for the codegen runtime |

The untyped server API (`Srv.Call` to `Srv.Reply`, with `Single`, `Many` or `NoRoute`) and the
untyped client API are described in `src/README-api.md`.

## Laws

`LAWS.bend` holds the protocol facts that must never break. `PROOF.bend` proves each one, and
`bend PROOF.bend` refuses the build when a change breaks a law. Some of them:

- every error code's wire name parses back to the same code;
- no error code is ever sent as HTTP 200;
- any method other than POST or GET is answered 405, whatever the path, query or headers;
- the content types the library emits for JSON and Protobuf parse back to the same codec and kind;
- the compressed and end-of-stream envelope flags are distinct bits;
- timeouts too large for 32 bits are clamped, not wrapped.

The transport (`src/transport/`) sits on [bend-kit-http](https://hub.bend-lang.com/n/bend-kit-http),
whose socket loops use `@unsafe` recursion. It is kept out of `PROOF.bend` on purpose, so the
proof gate covers the protocol logic, not the network loop.

## Testing

```sh
tests/run_all.sh                       # proof gate + unit tests (incl. a Bend client/server loopback)
tests/interop/run_server_interop.sh    # connect-go client -> Bendonette server (52 cases)
tests/interop/run_client_interop.sh    # Bendonette client -> connect-go server
tests/codegen/run.sh                   # generator: golden vectors vs protobuf-go, greet e2e
```

The interop and codegen tests need Go and buf.

## Limitations (v1)

- **No bidirectional streaming.** It needs HTTP/2, and there is no HTTP/2 server for Bend yet.
  Generated servers answer bidi methods with `unimplemented`.
- **Buffered request streams.** A client stream reaches the handler once the whole request body
  has arrived. Server streams are sent incrementally.
- **Identity compression only.** Requests with gzip, br or zstd get `unimplemented`, as the
  protocol requires.
- **`double` is held as `F32`**, so precision beyond float32 is lost (the 64-bit wire format is
  kept). Well-known types (Timestamp, Duration, ...) get no special JSON mapping. Generated
  code supports proto3 only.
- **Keep-alive latency.** bend-kit-http writes a response's head and body as separate sends, so
  unary latency on a reused connection can reach about 40 ms (Nagle plus delayed ACK).

## License

Apache-2.0
