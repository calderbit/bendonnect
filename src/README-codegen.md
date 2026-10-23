# Codegen contract (lead-owned): protoc-gen-bend + its Bend runtime

Goal: from a .proto file, generate one Bend module with typed messages, proto-binary and
proto3-JSON codecs, and typed Connect server/client stubs built on src/transport.

## Value mapping (all generated messages are `is Data`, so users may copy them with `+`)
| proto                         | Bend field type                       | default        |
|-------------------------------|---------------------------------------|----------------|
| string                        | String                                | ""             |
| bytes                         | List<&2, U32>  (one byte per cell)    | []             |
| bool                          | Bool                                  | False{}        |
| int32 uint32 sint32 fixed32 sfixed32 | U32 (two's complement for signed) | 0         |
| int64 uint64 sint64 fixed64 sfixed64 | Pb.Word64 (hi, lo; two's complement) | Word64{0,0} |
| float                         | F32                                   | 0.0            |
| double                        | F32  (LOSSY: documented limitation; wire stays 64-bit) | 0.0 |
| enum E                        | U32 (the number) + generated `E.<VALUE>()` constants and `E.name(+n) -> String`, `E.from_name(+s) -> Maybe<&2,U32>` | 0 |
| message M (singular)          | Maybe<&2, M>                          | None{}         |
| repeated T                    | List<&2, T>                           | []             |
| map<K, V>                     | List<&2, <Msg>.<Field>Entry> (generated `is Data` entry type {key, value}) | [] |
| oneof o { ... }               | generated sum `type <Msg>.<O> is Data: <Msg>.<O>.None{} | <Msg>.<O>.<Member>{value: T} ...` | None |
| proto3 `optional` scalar      | Maybe<&2, T>                          | None{}         |
Unknown fields are dropped on decode. Well-known types get no special JSON mapping (v1 limitation).

## Runtime modules (pure, no transport): src/pb.bend (alias Pbr), src/pbjson.bend (alias Pj)
Built on bend-kit-protobuf@0.1.0.0/protobuf.bend (alias Pb: Word64, Value, Field, decode, encode,
packed_decode/encode, from_*/to_* scalar helpers), bend-kit-json, bend-kit-bytes.
Pbr (proto binary) must provide at least:
  bytes.of_list(xs: List<&2,U32>) -> Bytes.Bytes ; bytes.to_list(b) -> List<&2,U32>
  string.encode(+s) -> Bytes (UTF-8) ; string.decode(b) -> Result<&2,&1,String,String> (strict UTF-8)
  zigzag32 / zigzag64 encode+decode ; f32 <-> bits ; double bits <-> F32 (round to nearest)
  Value constructors from each Bend scalar for each proto scalar kind, and the inverse readers
  returning Result<&2,&1,String,T> (wrong wire type -> Fail); repeated readers accepting BOTH packed
  and unpacked encodings, appending to an accumulator list
  decode(b) -> Result<&2,&1,String,List<&1,Pb.Field>> ; encode(List<&1,Pb.Field>) -> Bytes.Bytes
  word64.show_u / show_s (decimal), word64.read_u / read_s (decimal String -> Maybe)
Pj (proto3 JSON) must provide at least:
  obj builder helpers that omit default-valued fields; key lookup accepting the lowerCamelCase json
  name OR the original proto field name; int64 kinds as decimal strings (accept number or string on
  input); bytes as std base64 with padding (accept url-safe/unpadded); enums as names (accept numbers);
  F32 as JSON number, "NaN"/"Infinity"/"-Infinity" strings; null => default.
Both runtime files must print ALL PROOFS CHECK.

## Typed RPC adapters: src/transport/rpc.bend (alias Rpc) — imports Srv, Cli
  type Ctx is Data: Ctx{procedure: String, codec: P.Codec, headers: Map<&2,List<&2,String>>}
  type Out is Type: Out{sink: Srv.Sink, codec: P.Codec}     -- typed server-stream sender
  Rpc.send(out: Out, ~enc: P.Codec -> T -> Bytes, msg) -> IO(Out)   (or generated per-message send)
  adapters turning (decode, encode, impl) templates into Srv.Reply for unary / server-stream / client-stream;
  bidi -> Unimplemented. Decode failure -> invalid_argument. Custom codec -> server replies 415 earlier?
  no: classify accepts it, so adapter returns Unimplemented "codec x not supported".

## Generated module for package greet.v1, file greet.proto -> greet_pb.bend (Bend module names cannot contain dots) (user imports it `as G`)
  type HelloRequest is Data: HelloRequest{name: String, ...}
  HelloRequest.default() ; HelloRequest.encode_proto(m) -> Bytes ; HelloRequest.decode_proto(b) -> Result<&2,&1,String,HelloRequest>
  HelloRequest.to_json(m) -> Json.Val ; HelloRequest.encode_json(m) -> Bytes
  HelloRequest.from_json(v) -> Result<&2,&1,String,HelloRequest> ; HelloRequest.decode_json(b) -> Result<...>
  HelloRequest.encode(+codec, m) -> Bytes ; HelloRequest.decode(+codec, b) -> Result<&1,&1,E.Error,HelloRequest>  (E.Error is Type-kinded)
  GreetService.Greet.procedure() -> "greet.v1.GreetService/Greet"
  Server: GreetService.handle(~greet: Rpc.Ctx -> HelloRequest -> IO(Result<&1,&1,E.Error,HelloReply>),
                              ~greet_many: Rpc.Ctx -> HelloRequest -> Rpc.Out -> IO(Rpc.Out & Result<&1,&1,E.Error,Unit>),
                              ~greet_all: Rpc.Ctx -> List<&2,HelloRequest> -> IO(Result<&1,&1,E.Error,HelloReply>),
                              call: Srv.Call) -> IO(Srv.Reply)      (one template per method, in .proto order;
                              unknown procedure -> Srv.NoRoute{})
          GreetService.GreetMany.send(out: Rpc.Out, msg: HelloReply) -> IO(Rpc.Out)
          GreetService.owns(+procedure) -> Bool
  Client: GreetService.greet(base_url, +codec, headers, req) -> IO(Result<&1,&1,E.Error,HelloReply>)
          GreetService.greet_many(base_url, +codec, headers, req) -> IO(Result<&1,&1,E.Error,List<&2,HelloReply>>)
          GreetService.greet_all(base_url, +codec, headers, reqs: List<&2,HelloRequest>) -> IO(Result<...HelloReply>)
  Method template/def names are snake_case of the RPC name. Bend name collisions with keywords
  (type, match, case, def, law, for, exs, import, as, is, do, return, Kind, Type, Data) get a trailing '_'.
  Generated messages for transports: the server/client parts go in a SECOND file greet_connect.bend so that
  greet_pb.bend stays pure and provable (it must print ALL PROOFS CHECK).
