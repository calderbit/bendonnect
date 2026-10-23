# Loopback test for src/transport/rpc.bend: a hand-written "generated" service served and called
# in one process on 127.0.0.1:18931 (HTTP/1.1). Run: `bend tests/rpc_test.bend` (needs a C compiler;
# exits 0 when done). Failures print as `"FAIL name` (see run_all.sh).
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-json@0.6.1.1/json.bend as Json
import bend-kit-protobuf@0.1.0.0/protobuf.bend as Pb
import ../src/code.bend as Code
import ../src/error.bend as E
import ../src/protocol.bend as P
import ../src/pb.bend as Pbr
import ../src/pbjson.bend as Pj
import ../src/transport/server.bend as Srv
import ../src/transport/client.bend as Cli
import ../src/transport/rpc.bend as Rpc

# ------------------------------------------------------------------ messages (shape of generated code)

type HelloRequest is Data:
  HelloRequest{name: String}

type HelloReply is Data:
  HelloReply{message: String}

def bad_msg(+m: String) -> E.Error:
  E.new(Code.InvalidArgument{}, m)

def to_err(-T: Type, r: Result<&2, &1, String, T>) -> Result<&1, &1, E.Error, T>:
  match r:
    case Fail{m}:
      Fail{bad_msg(m)}
    case Done{x}:
      Done{x}

def HelloRequest.default() -> HelloRequest:
  HelloRequest{""}

def HelloRequest.set_proto(+m: HelloRequest, +num: U32, v: Pb.Value) -> Result<&2, &1, String, HelloRequest>:
  match num:
    case 1:
      do Result<&2, &1, String, HelloRequest>:
        s : String <- Pbr.read.string(v)
        return HelloRequest{s}
    case _:
      Done{m}

def HelloRequest.fold_proto(fs: List<&1, Pb.Field>, m: HelloRequest) -> Result<&2, &1, String, HelloRequest>:
  match fs:
    case Nil{}:
      Done{m}
    case Con{Pb.Field{num, v}, t}:
      do Result<&2, &1, String, HelloRequest>:
        m2 : HelloRequest <- HelloRequest.set_proto(m, num, v)
        HelloRequest.fold_proto(t, m2)

def HelloRequest.from_fields(r: Result<&2, &1, String, List<&1, Pb.Field>>) -> Result<&2, &1, String, HelloRequest>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{fs}:
      HelloRequest.fold_proto(fs, HelloRequest.default())

def HelloRequest.decode_proto(b: Bytes.Bytes) -> Result<&2, &1, String, HelloRequest>:
  HelloRequest.from_fields(Pbr.decode(b))

def HelloRequest.encode_proto(+m: HelloRequest) -> Bytes.Bytes:
  HelloRequest{+name} = m
  Pbr.encode(Pbr.field.string(1, name))

def HelloRequest.json_set(+m: HelloRequest, +num: U32, v: Json.Val) -> Result<&2, &1, String, HelloRequest>:
  match num:
    case 1:
      do Result<&2, &1, String, HelloRequest>:
        s : String <- Pj.read.string(v)
        return HelloRequest{s}
    case _:
      Done{m}

def HelloRequest.json_fold(kvs: List<&1, String & Json.Val>, m: HelloRequest) -> Result<&2, &1, String, HelloRequest>:
  match kvs:
    case Nil{}:
      Done{m}
    case Con{(k, v), t}:
      do Result<&2, &1, String, HelloRequest>:
        m2 : HelloRequest <- HelloRequest.json_set(m, Pj.dispatch(k, [Pj.JKey{"name", 1}]), v)
        HelloRequest.json_fold(t, m2)

def HelloRequest.from_json(v: Json.Val) -> Result<&2, &1, String, HelloRequest>:
  do Result<&2, &1, String, HelloRequest>:
    kvs : List<&1, String & Json.Val> <- Pj.fields(v)
    HelloRequest.json_fold(kvs, HelloRequest.default())

def HelloRequest.decode_json(b: Bytes.Bytes) -> Result<&2, &1, String, HelloRequest>:
  do Result<&2, &1, String, HelloRequest>:
    v : Json.Val <- Pj.parse(b)
    HelloRequest.from_json(v)

def HelloRequest.to_json(+m: HelloRequest) -> Json.Val:
  HelloRequest{+name} = m
  Pj.obj(Pj.put.string("name", name, Nil{}))

def HelloRequest.encode(+codec: P.Codec, m: HelloRequest) -> Bytes.Bytes:
  match codec:
    case P.Proto{}:
      HelloRequest.encode_proto(m)
    case P.Json{}:
      Pj.encode(HelloRequest.to_json(m))
    case P.Custom{n}:
      Bytes.new(0)

def HelloRequest.decode(+codec: P.Codec, b: Bytes.Bytes) -> Result<&1, &1, E.Error, HelloRequest>:
  match codec:
    case P.Proto{}:
      to_err(HelloRequest, HelloRequest.decode_proto(b))
    case P.Json{}:
      to_err(HelloRequest, HelloRequest.decode_json(b))
    case P.Custom{n}:
      Fail{E.new(Code.Unimplemented{}, "codec")}

def HelloReply.default() -> HelloReply:
  HelloReply{""}

def HelloReply.set_proto(+m: HelloReply, +num: U32, v: Pb.Value) -> Result<&2, &1, String, HelloReply>:
  match num:
    case 1:
      do Result<&2, &1, String, HelloReply>:
        s : String <- Pbr.read.string(v)
        return HelloReply{s}
    case _:
      Done{m}

def HelloReply.fold_proto(fs: List<&1, Pb.Field>, m: HelloReply) -> Result<&2, &1, String, HelloReply>:
  match fs:
    case Nil{}:
      Done{m}
    case Con{Pb.Field{num, v}, t}:
      do Result<&2, &1, String, HelloReply>:
        m2 : HelloReply <- HelloReply.set_proto(m, num, v)
        HelloReply.fold_proto(t, m2)

def HelloReply.from_fields(r: Result<&2, &1, String, List<&1, Pb.Field>>) -> Result<&2, &1, String, HelloReply>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{fs}:
      HelloReply.fold_proto(fs, HelloReply.default())

def HelloReply.decode_proto(b: Bytes.Bytes) -> Result<&2, &1, String, HelloReply>:
  HelloReply.from_fields(Pbr.decode(b))

def HelloReply.json_set(+m: HelloReply, +num: U32, v: Json.Val) -> Result<&2, &1, String, HelloReply>:
  match num:
    case 1:
      do Result<&2, &1, String, HelloReply>:
        s : String <- Pj.read.string(v)
        return HelloReply{s}
    case _:
      Done{m}

def HelloReply.json_fold(kvs: List<&1, String & Json.Val>, m: HelloReply) -> Result<&2, &1, String, HelloReply>:
  match kvs:
    case Nil{}:
      Done{m}
    case Con{(k, v), t}:
      do Result<&2, &1, String, HelloReply>:
        m2 : HelloReply <- HelloReply.json_set(m, Pj.dispatch(k, [Pj.JKey{"message", 1}]), v)
        HelloReply.json_fold(t, m2)

def HelloReply.from_json(v: Json.Val) -> Result<&2, &1, String, HelloReply>:
  do Result<&2, &1, String, HelloReply>:
    kvs : List<&1, String & Json.Val> <- Pj.fields(v)
    HelloReply.json_fold(kvs, HelloReply.default())

def HelloReply.decode_json(b: Bytes.Bytes) -> Result<&2, &1, String, HelloReply>:
  do Result<&2, &1, String, HelloReply>:
    v : Json.Val <- Pj.parse(b)
    HelloReply.from_json(v)

def HelloReply.to_json(+m: HelloReply) -> Json.Val:
  HelloReply{+message} = m
  Pj.obj(Pj.put.string("message", message, Nil{}))

def HelloReply.encode_proto(+m: HelloReply) -> Bytes.Bytes:
  HelloReply{+message} = m
  Pbr.encode(Pbr.field.string(1, message))

def HelloReply.encode(+codec: P.Codec, m: HelloReply) -> Bytes.Bytes:
  match codec:
    case P.Proto{}:
      HelloReply.encode_proto(m)
    case P.Json{}:
      Pj.encode(HelloReply.to_json(m))
    case P.Custom{n}:
      Bytes.new(0)

def HelloReply.decode(+codec: P.Codec, b: Bytes.Bytes) -> Result<&1, &1, E.Error, HelloReply>:
  match codec:
    case P.Proto{}:
      to_err(HelloReply, HelloReply.decode_proto(b))
    case P.Json{}:
      to_err(HelloReply, HelloReply.decode_json(b))
    case P.Custom{n}:
      Fail{E.new(Code.Unimplemented{}, "codec")}

# ------------------------------------------------------------------ the service (what a user writes)

def greet_impl.go(+bad: Bool, +name: String) -> Result<&1, &1, E.Error, HelloReply>:
  Bool.pick(Result<&1, &1, E.Error, HelloReply>, bad, Fail{E.new(Code.InvalidArgument{}, "bad name")}, Done{HelloReply{String.append(String.append("Hello, ", name), "!")}})

def greet_impl(ctx: Rpc.Ctx, req: HelloRequest) -> IO(Result<&1, &1, E.Error, HelloReply>):
  HelloRequest{+name} = req
  IO.pure(Result<&1, &1, E.Error, HelloReply>, greet_impl.go(String.eq(name, "fail"), name))

def send_reply(out: Rpc.Out, +text: String) -> IO(Rpc.Out):
  Rpc.send(~HelloReply, ~HelloReply.encode, out, HelloReply{text})

def many_impl(ctx: Rpc.Ctx, req: HelloRequest, out: Rpc.Out) -> IO(Rpc.Out & Result<&1, &1, E.Error, Unit>):
  HelloRequest{+name} = req
  do IO<Rpc.Out & Result<&1, &1, E.Error, Unit>>:
    o1 : Rpc.Out <- send_reply(out, String.append(name, "#1"))
    o2 : Rpc.Out <- send_reply(o1, String.append(name, "#2"))
    o3 : Rpc.Out <- send_reply(o2, String.append(name, "#3"))
    return (o3, Done{Unit{}})

def join_names(xs: List<&2, HelloRequest>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{HelloRequest{n}, t}:
      String.concat([n, "+", join_names(t)])

def all_impl(ctx: Rpc.Ctx, reqs: List<&2, HelloRequest>) -> IO(Result<&1, &1, E.Error, HelloReply>):
  IO.pure(Result<&1, &1, E.Error, HelloReply>, Done{HelloReply{join_names(reqs)}})

# ------------------------------------------------------------------ "generated" handle: route chain

def Svc.handle(~greet: Rpc.Ctx -> HelloRequest -> IO(Result<&1, &1, E.Error, HelloReply>), ~many: Rpc.Ctx -> HelloRequest -> Rpc.Out -> IO(Rpc.Out & Result<&1, &1, E.Error, Unit>), ~all: Rpc.Ctx -> List<&2, HelloRequest> -> IO(Result<&1, &1, E.Error, HelloReply>), call: Srv.Call) -> IO(Srv.Reply):
  Rpc.route(
    ~(c => Rpc.unary(~HelloRequest, ~HelloReply, ~HelloRequest.decode, ~HelloReply.encode, ~greet, c)),
    ~(c => Rpc.route(
        ~(c2 => Rpc.server_stream(~HelloRequest, ~HelloRequest.decode, ~many, c2)),
        ~(c2 => Rpc.route(
            ~(c3 => Rpc.client_stream(~HelloRequest, ~HelloReply, ~HelloRequest.decode, ~HelloReply.encode, ~all, c3)),
            ~(c3 => Rpc.route(~(c4 => Rpc.bidi_unimplemented(c4)), ~(c4 => Rpc.no_route(c4)), "greet.v1.Svc/Chat", c3)),
            "greet.v1.Svc/GreetAll", c2)),
        "greet.v1.Svc/GreetMany", c)),
    "greet.v1.Svc/Greet", call)

def handle(call: Srv.Call) -> IO(Srv.Reply):
  Svc.handle(~greet_impl, ~many_impl, ~all_impl, call)

# ------------------------------------------------------------------ client side

def base() -> String:
  "http://127.0.0.1:18931"

def no_headers() -> Map<&2, List<&2, String>>:
  Map.new(&2, List<&2, String>)

def greet(+codec: P.Codec, req: HelloRequest) -> IO(Result<&1, &1, E.Error, HelloReply>):
  Rpc.call.unary(~HelloRequest, ~HelloReply, ~HelloReply.decode, ~HelloRequest.encode, base(), "greet.v1.Svc/Greet", codec, no_headers(), req)

def greet_many(+codec: P.Codec, req: HelloRequest) -> IO(Result<&1, &1, E.Error, List<&2, HelloReply>>):
  Rpc.call.server_stream(~HelloRequest, ~HelloReply, ~HelloReply.decode, ~HelloRequest.encode, base(), "greet.v1.Svc/GreetMany", codec, no_headers(), req)

def greet_all(+codec: P.Codec, reqs: List<&2, HelloRequest>) -> IO(Result<&1, &1, E.Error, HelloReply>):
  Rpc.call.client_stream(~HelloRequest, ~HelloReply, ~HelloReply.decode, ~HelloRequest.encode, base(), "greet.v1.Svc/GreetAll", codec, no_headers(), reqs)

def chat(+codec: P.Codec, req: HelloRequest) -> IO(Result<&1, &1, E.Error, HelloReply>):
  Rpc.call.unary(~HelloRequest, ~HelloReply, ~HelloReply.decode, ~HelloRequest.encode, base(), "greet.v1.Svc/Chat", codec, no_headers(), req)

def missing(+codec: P.Codec, req: HelloRequest) -> IO(Result<&1, &1, E.Error, HelloReply>):
  Rpc.call.unary(~HelloRequest, ~HelloReply, ~HelloReply.decode, ~HelloRequest.encode, base(), "greet.v1.Svc/Nope", codec, no_headers(), req)

# ------------------------------------------------------------------ assertions

def msg_of(r: Result<&1, &1, E.Error, HelloReply>) -> String:
  match r:
    case Fail{e}:
      E.Error{code, m, ds} = e
      String.concat(["err:", Code.to_string(code), ":", m])
    case Done{HelloReply{m}}:
      m

def msgs_of.go(xs: List<&2, HelloReply>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{HelloReply{m}, t}:
      String.concat([m, ",", msgs_of.go(t)])

def msgs_of(r: Result<&1, &1, E.Error, List<&2, HelloReply>>) -> String:
  match r:
    case Fail{e}:
      E.Error{code, m, ds} = e
      String.concat(["err:", Code.to_string(code), ":", m])
    case Done{xs}:
      msgs_of.go(xs)

def expect(+name: String, +got: String, +want: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(got, want), IO.print(String.append("PASS ", name)), IO.print(String.concat(["\"FAIL ", name, ": got ", got, " want ", want])))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.spawn(Unit, Srv.serve(~handle, ~"", "127.0.0.1", 18931))
    IO.sleep(300)
    r1 : Result<&1, &1, E.Error, HelloReply> <- greet(P.Proto{}, HelloRequest{"Ann"})
    expect("unary proto", msg_of(r1), "Hello, Ann!")
    r2 : Result<&1, &1, E.Error, HelloReply> <- greet(P.Json{}, HelloRequest{"Bob"})
    expect("unary json", msg_of(r2), "Hello, Bob!")
    r3 : Result<&1, &1, E.Error, HelloReply> <- greet(P.Proto{}, HelloRequest{"fail"})
    expect("unary error", msg_of(r3), "err:invalid_argument:bad name")
    r4 : Result<&1, &1, E.Error, List<&2, HelloReply>> <- greet_many(P.Proto{}, HelloRequest{"x"})
    expect("server stream proto", msgs_of(r4), "x#1,x#2,x#3,")
    r5 : Result<&1, &1, E.Error, List<&2, HelloReply>> <- greet_many(P.Json{}, HelloRequest{"y"})
    expect("server stream json", msgs_of(r5), "y#1,y#2,y#3,")
    r6 : Result<&1, &1, E.Error, HelloReply> <- greet_all(P.Proto{}, [HelloRequest{"a"}, HelloRequest{"b"}])
    expect("client stream proto", msg_of(r6), "a+b+")
    r7 : Result<&1, &1, E.Error, HelloReply> <- greet_all(P.Json{}, [HelloRequest{"c"}])
    expect("client stream json", msg_of(r7), "c+")
    r8 : Result<&1, &1, E.Error, HelloReply> <- chat(P.Proto{}, HelloRequest{"z"})
    expect("bidi is unimplemented", msg_of(r8), "err:unimplemented:bidirectional streaming is not supported")
    r9 : Result<&1, &1, E.Error, HelloReply> <- missing(P.Proto{}, HelloRequest{"z"})
    expect("unknown procedure is not_found", msg_of(r9), "err:not_found:no such procedure")
    IO.exit(0)
