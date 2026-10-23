# Codegen runtime reference

Modules: `src/pb.bend` (alias Pbr, proto binary), `src/pbjson.bend` (alias Pj, proto3 JSON),
`src/transport/rpc.bend` (alias Rpc, typed server/client adapters). Pbr and Pj are pure and print
ALL PROOFS CHECK; Rpc imports the transports (unsafe notice expected). Working models of generated code
(decode fold, encode, JSON, handle route chain, client calls) are in `tests/pb_test.bend`,
`tests/pbjson_test.bend` and `tests/rpc_test.bend`: copy their shapes.

```
import bend-kit-protobuf@0.1.0.0/protobuf.bend as Pb
import bend-kit-json@0.6.1.1/json.bend as Json
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import <path>/src/pb.bend as Pbr
import <path>/src/pbjson.bend as Pj
import <path>/src/transport/rpc.bend as Rpc     (only the .connect file)
```
Kinds `K`: double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64
bool string bytes enum message. Bend types: 32-bit ints and enums `U32` (two's complement), 64-bit ints
`Pb.Word64{hi, lo}`, float and double `F32` (double is lossy), `Bool`, `String`, bytes `List<&2,U32>`.
`R<T>` = `Result<&2, &1, String, T>`.

## Bend rules that shape generated code (learned the hard way)
- `match` only on a parameter or pattern variable: never on a call (`match f(x):` and `(a, b) = f(x)` are
  rejected). Give every Result/Maybe/tuple consumer its own def with the value as a parameter.
- A callee must be declared ABOVE its caller (no forward references), no mutual recursion.
- Destructure `m` before matching on a later parameter: `def set(+m: M, +num: U32, v)`: `M{...} = m` then `match num:`.
- Operators need a type: `(a + b : U32)`. Constructors named like Base ones (`Key`, `Text`, `Move`...) clash.
- Template params (`~x`) come first; a template arg may be a def name (`~Msg.decode`) or a closed lambda
  (`~(c => f(~g, c))`, may mention template params of the enclosing template). A def with a `+x` param
  needs a `@+x:` arrow in the template type; the runtime already declares those.
- F32 primitives (`F32.bits`, `F32.show`, `F32.read`, F32 arithmetic) are opaque to the checker: tests that touch
  them must use an `IO` main (compiled natively). `bend src/x.bend` (check only) is unaffected.

## Pbr: decoding
`Pbr.decode(b: Bytes) -> R<List<&1,Pb.Field>>` then fold over the fields: `match Pb.Field{n, v}`, dispatch on `n`
with a `match num: case 1: ...` (U32 literal patterns), call `Pbr.read.K(v)`; `case _:` drops unknown fields.
Last scalar wins; nested messages are replaced, not merged. Wrong wire type or malformed input -> `Fail{reason}`.
- `Pbr.read.K(v: Pb.Value) -> R<T>` for every kind except message; `Pbr.read.message(v) -> R<List<&1,Pb.Field>>`
  (nested decode; run the nested fold on it); `Pbr.read.blob(v) -> R<Bytes>` raw length-delimited payload;
  `Pbr.read.bytes -> R<List<&2,U32>>`; `Pbr.read.double` rounds the 64-bit wire value to F32.
- `Pbr.read.repeated.K(v, acc: List<&2,T>) -> R<List<&2,T>>` for double float int32 int64 uint32 uint64 sint32 sint64
  fixed32 fixed64 sfixed32 sfixed64 bool enum (accepts a packed Blob or one unpacked value) and for string, bytes
  (one element per field). **The accumulator is in REVERSE order**: it conses; call `Pbr.rev(T, acc)` once after
  the fold. There is no repeated.message: `read.message` + your own cons.
- `Pbr.rev(-A: Data, xs)` list reverse; `Pbr.cat(a, b)` and `Pbr.cat.all(parts)` concat `List<&1,Pb.Field>`.

## Pbr: encoding
`Pbr.encode(fs: List<&1,Pb.Field>) -> Bytes` (a bad field number yields empty bytes). Build `fs` with
`Pbr.cat.all([Pbr.field.string(1, m.name), Pbr.field.int32(2, m.n), ...])` in field-number order.
- `Pbr.field.K(+n: U32, x) -> List<&1,Pb.Field>`: `[]` when x is the proto3 default (0, 0.0 with all-zero bits,
  false, "", empty bytes, zero Word64). `Pbr.field.K.always(+n, x)`: exactly one field (oneof members, `optional`).
- `Pbr.field.repeated.K(+n, xs: List<&2,T>)`: packed for numeric/bool/enum kinds, one field per element for
  string/bytes; `[]` for an empty list.
- messages: `Pbr.field.message(+n, fs)` (always emitted, even if `fs` is `[]`; same as `.message.always`),
  `Pbr.field.repeated.message(+n, items: List<&1, List<&1,Pb.Field>>)`. `fs` is the nested message's own field list.
- `Pbr.value.K(x) -> Pb.Value` constructors (`value.message(fs)` too).
- Enums are `field.enum` / `read.enum` / `read.repeated.enum` (int32 semantics, so -1 is 10 bytes).
- map<K,V>: encode each entry as a message with fields 1 (key) and 2 (value) via `field.repeated.message`.

## Pbr: helpers
- `Pbr.bytes.of_list(xs) -> Bytes`, `Pbr.bytes.to_list(b) -> List<&2,U32>`
- `Pbr.string.encode(+s) -> Bytes` (UTF-8, lenient), `Pbr.string.decode(b) -> R<String>` (strict UTF-8)
- `Pbr.zigzag32(+v)`, `Pbr.unzigzag32(+v)`, `Pbr.zigzag64(w)`, `Pbr.unzigzag64(w)`
- `Pbr.f32.bits(+f: F32) -> U32`, `Pbr.f32.of_bits(+u) -> F32`; `Pbr.double.bits(+f) -> Pb.Word64`,
  `Pbr.double.of_bits(w) -> F32` (round to nearest even, overflow -> inf, tiny -> 0, NaN kept);
  pure bit versions `Pbr.double.of_f32bits(+b: U32) -> Word64`, `Pbr.double.f32bits(w) -> U32`
- Word64: `Pbr.word64.show_u(+w) -> String`, `show_s(+w)` (two's complement), `read_u(+s) -> Maybe<&2,Word64>`
  (digits only, None past 2^64-1), `read_s(+s)` (optional `-`, int64 range), `of_u32(+x)`, `of_i32(+x)` (sign extend),
  `hi(w)`, `lo(w)`, `is_zero(w)`, `is_neg(w)`, `eq(a, b)`, `neg(w)`, `shl(w, +n)`, `shr(w, +n)` (n < 64)
- `Pbr.max_size() = 2^31-1`, `Pbr.max_depth() = 100n` (limits passed to Pb.decode/encode)

## Pj: writing JSON
Accumulate in REVERSE (each `put` conses onto `acc`, innermost call = first field) and finish with `Pj.obj`:
`Pj.obj(Pj.put.int32("b", m.b, Pj.put.string("a", m.a, Nil{})))` gives `{"a":..,"b":..}`. Names are the lowerCamel json name.
`acc: List<&1, Bytes.Bytes & Json.Val>`.
- `Pj.obj(acc) -> Json.Val`; `Pj.encode(v) -> Bytes` (compact); `Pj.parse(b) -> R<Json.Val>`
- `Pj.put.K(+json_name, x, acc)`: skips defaults; `Pj.put.K.always(...)`: always (oneof, optional).
  K: all kinds except enum/message listed above. 64-bit ints are quoted decimal strings (uint64 unsigned),
  32-bit ints are numbers, bytes are padded std base64, F32 via `F32.show` (shortest round-trip), non-finite
  as `"NaN"`, `"Infinity"`, `"-Infinity"`.
- enums: `Pj.put.enum(~name, +json_name, +x, acc)` / `.always`, `Pj.put.repeated.enum(~name, +json_name, xs, acc)`
  where `~name: @+n: U32 -> String` is the generated `E.name`; it must return `""` for an unknown number
  (then the number is printed). Default 0 is skipped by `put.enum`.
- `Pj.put.repeated.K(+json_name, xs: List<&2,T>, acc)` (omitted when empty);
  `Pj.put.message(+json_name, v: Json.Val, acc)` with `v = Msg.to_json(m)` (always emitted),
  `Pj.put.repeated.message(+json_name, vs: List<&1,Json.Val>, acc)`.
- maps: `Pj.put.map(+json_name, entries: List<&1, Bytes & Json.Val>, acc)` (omitted when empty) with entries from
  `Pj.entry(Pj.key.K(k), Pj.val.V(v))`; `Pj.key.K(x) -> String` exists for int/uint/sint/fixed/sfixed 32+64, bool, string.
- `Pj.val.K(x) -> Json.Val` (and `Pj.val.enum(~name, +x)`) for building elements yourself.

## Pj: reading JSON (same fold shape as binary)
```
kvs <- Pj.fields(v)                          # R<List<&1, String & Json.Val>>; non-object (incl. null) -> Fail
fold: match kvs: Con{(k, v), t}: m2 <- M.json_set(m, Pj.dispatch(k, M.json_keys()), v); fold(t, m2)
M.json_keys() -> List<&2, Pj.JKey>           # [Pj.JKey{"userName", 1}, Pj.JKey{"user_name", 1}, ...] json name AND proto name
M.json_set(+m, +num: U32, v) matches num; `case _:` ignores unknown keys
```
- `Pj.dispatch(+k, table: List<&2,Pj.JKey>) -> U32` field number or 0 (unknown key).
- `Pj.read.K(v: Json.Val) -> R<T>`: null -> default; numbers accepted as JSON number or string (decimal, range
  checked, no `1e3`/`1.0` forms for integers); bool needs a JSON boolean; floats accept numbers, numeric strings
  and `"NaN"/"Infinity"/"-Infinity"`; bytes accept std or url-safe base64, padded or not.
- `Pj.read.enum(~from_name, v)` with `~from_name: @+s: String -> Maybe<&2,U32>` (the generated `E.from_name`):
  name or number, null -> 0, unknown name -> Fail, unknown number kept.
- `Pj.read.repeated.K(v)`, `Pj.read.repeated.enum(~from_name, v)`, generic `Pj.read.repeated(~T, ~read, v)`
  (pass `~M.from_json` for messages); null -> `[]`.
- `Pj.read.opt(~T, ~read, v) -> R<Maybe<&2,T>>`: null -> None else Some(read v). Use for optional scalars,
  oneof members and singular messages (`~M.from_json`).
- maps: `Pj.read.map(~K, ~V, ~E, ~key, ~value, ~mk, v) -> R<List<&2,E>>` with `~key` = `~Pj.read.key.K`
  (`@+s: String -> R<K>`), `~value` = `~Pj.read.V` or `~M.from_json`, `~mk` = `~(+k => +v => Entry{k, v})`;
  null -> `[]`. Lower level: `Pj.read.map.entries(v)`.
- `Pj.take(kvs, +json_name, +proto_name) -> Json.Val & rest` is an alternative to the fold (value is `Json.Null{}`
  when absent). It returns a pair, so use it only where the pair arrives as a parameter.

## Rpc (src/transport/rpc.bend)
```
type Ctx is Data: Ctx{procedure: String, codec: P.Codec, headers: Map<&2,List<&2,String>>}
type Out is Type: Out{sink: Srv.Sink, codec: P.Codec}
```
Template arg types used below (note `E.Error` is Type kind, so these Results are `&1,&1`, NOT `&2,&1`):
`DEC(T) = @+codec: P.Codec -> Bytes.Bytes -> Result<&1,&1,E.Error,T>` (the generated `T.decode(+codec, b)`),
`ENC(T) = @+codec: P.Codec -> T -> Bytes.Bytes` (the generated `T.encode(+codec, m)`).
Message types are passed as `~Req`, `~Res` (kind Data). Decode errors are returned to the caller unchanged, so
the generated `decode` should already use `invalid_argument`. A custom codec yields `unimplemented`.
- `Rpc.unary(~Req, ~Res, ~dec: DEC(Req), ~enc: ENC(Res), ~impl: Ctx -> Req -> IO(Result<&1,&1,E.Error,Res>), call: Srv.Call) -> IO(Srv.Reply)`
- `Rpc.server_stream(~Req, ~dec: DEC(Req), ~impl: Ctx -> Req -> Out -> IO(Out & Result<&1,&1,E.Error,Unit>), call) -> IO(Srv.Reply)` (no `~enc`: sending encodes)
- `Rpc.client_stream(~Req, ~Res, ~dec, ~enc, ~impl: Ctx -> List<&2,Req> -> IO(Result<&1,&1,E.Error,Res>), call) -> IO(Srv.Reply)`
- `Rpc.send(~T, ~enc: ENC(T), out: Out, msg: T) -> IO(Out)`; generated per-message send is
  `Rpc.send(~HelloReply, ~HelloReply.encode, out, msg)`
- `Rpc.bidi_unimplemented(call) -> IO(Srv.Reply)`, `Rpc.no_route(call) -> IO(Srv.Reply)` (Srv.NoRoute, HTTP 404)
- `Rpc.route(~hit: Srv.Call -> IO(Srv.Reply), ~miss: Srv.Call -> IO(Srv.Reply), +procedure: String, call) -> IO(Srv.Reply)`:
  if `call.procedure == procedure` then hit else miss; chain them and end with `~(c => Rpc.no_route(c))`
  (see `Svc.handle` in tests/rpc_test.bend). `GreetService.owns(+p)` can simply compare strings.
- client: `Rpc.call.unary(~Req, ~Res, ~dec: DEC(Res), ~enc: ENC(Req), base_url, procedure, +codec, headers, req) -> IO(Result<&1,&1,E.Error,Res>)`,
  `Rpc.call.server_stream(... , req) -> IO(Result<&1,&1,E.Error,List<&2,Res>>)` (collects all messages; an error
  end-stream fails the whole call), `Rpc.call.client_stream(..., reqs: List<&2,Req>) -> IO(Result<&1,&1,E.Error,Res>)`.
  Transport failures are `unavailable`; non-200 follows `E.from_http`.
- Other helpers (rarely needed): `Rpc.err_reply(e)`, `Rpc.bad_request(+msg)`, `Rpc.reply_io(r)`.

Limits: handlers cannot set response headers/trailers (meta is empty); no bidi; request bodies are buffered by the server.
