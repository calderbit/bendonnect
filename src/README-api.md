# Core API contract (lead-owned; agents implement to this)

Headers / metadata everywhere: `Map<&2, List<&2, String>>` with LOWERCASE keys (Base Map).

src/code.bend      (done)  Code type, to_string, from_string, to_http, from_http
src/b64.bend       encode_std(b) padded, encode_std_raw(b) unpadded, encode_url_raw(b) unpadded,
                   decode(+s) -> Maybe<&1, Bytes>  accepts std or url alphabet, padded or not
src/error.bend     type Detail is Type: Detail{type_name: String, value: Bytes, debug: Maybe<&1, Json.Val>}
                   type Error is Type: Error{code: Code, message: String, details: List<&1, Detail>}
                   new(code, message) -> Error
                   to_json(e) -> Json.Val ; encode(e) -> Bytes        (omit empty message/details; value = unpadded std b64)
                   from_json(v) -> Maybe<&1, Error> ; decode(b) -> Maybe<&1, Error>   ({}, code null, non-string code => None; unrecognized code string => Unknown)
                   from_http(+status: U32, body: Bytes) -> Error     (client: parse body, else infer via Code.from_http, message = HTTP status text)
                   type EndStream is Type: EndStream{error: Maybe<&1, Error>, metadata: Map<&2, List<&2, String>>}
                   end_encode(e) -> Bytes ; end_decode(b) -> Maybe<&1, EndStream>  (error:null/{} invalid)
src/metadata.bend  trailers_to_headers(m) -> Map  (prefix keys with "trailer-")
                   split_trailers(h) -> Map & Map (headers, trailers with prefix stripped)
                   is_reserved(+key) -> Bool ("connect-" prefix), is_binary(+key) ("-bin" suffix)
                   valid_key(+key) -> Bool  (1*[0-9a-z_.-])
src/envelope.bend  type Envelope is Type: Envelope{flags: U32, data: Bytes}
                   flag_compressed() = 1, flag_end() = 2
                   encode(e) -> Bytes  ; encode_all(List<&1, Envelope>) -> Bytes
                   type Step is Type: Need{buf: Bytes} | Got{env: Envelope, rest: Bytes} | Bad{reason: String}
                   decode(buf, +max) -> Step   (max = message size limit; Bad if exceeded)
                   decode_all(buf, +max) -> Result<&2, &1, String, List<&1, Envelope>>  (trailing partial => Fail)
src/protocol.bend  type Codec is Data: Json{} | Proto{} | Custom{name: String}
                   type CallKind is Data: Unary{} | UnaryGet{} | Stream{}   (Kind is reserved)
                   type Spec is Type: Spec{procedure: String, kind: CallKind, codec: Codec,
                     timeout_ms: Maybe<&2, U32>, encoding: String, accept: List<&2, String>, message: Bytes}
                     (message = decoded GET payload; empty for POST)
                   type Reject is Data: Status{status: U32, message: String} | Connect{code: Code, message: String}
                   classify(method, path, query, headers, prefix) -> Result<&2, &1, Reject, Spec>
                   unary_content_type(codec), stream_content_type(codec) -> String
                   parse_timeout(+s) -> Maybe<&2, U32>  (1..10 ASCII digits; clamp to U32 max)
                   supported_encodings() = ["identity"]  (gzip is future work)

## Transport (src/transport/*.bend, may use bend-kit-http / @unsafe)

Server (src/transport/server.bend), alias `Srv`:
  type Meta is Data: Meta{headers: Map<&2, List<&2, String>>, trailers: Map<&2, List<&2, String>>}
  type Call is Type: Call{procedure: String, kind: P.CallKind, codec: P.Codec,
    headers: Map<&2, List<&2, String>>, timeout_ms: Maybe<&2, U32>, messages: List<&1, Bytes>}
    (unary/GET: exactly one message; stream: every request envelope's payload, in order)
  type Sink is Type     -- wraps the HTTP writer for a server stream
  send(sink: Sink, msg: Bytes) -> IO(Sink)      -- writes one enveloped message (flushed)
  type Reply is Type:
    Single{result: Result<&1, &1, E.Error, Bytes>, meta: Meta}   -- unary, or client-stream single response
    Many{run: Sink -> IO(Sink & Result<&1, &1, E.Error, Unit>), meta: Meta}   -- server stream
    NoRoute{}                                                         -- unknown procedure: HTTP 404
  serve(~handle: Call -> IO(Reply), host: String, +port: U32, prefix: String) -> IO(Unit)
  helpers: ok(msg) -> Reply ; fail(code, message) -> Reply ; meta.empty()
Client (src/transport/client.bend), alias `Cli`:
  type Response is Type: Response{headers: Map, trailers: Map, messages: List<&1, Bytes>}
  unary(base_url, procedure, codec, headers, msg: Bytes) -> IO(Result<&1, &1, E.Error, Response>)
  get(base_url, procedure, codec, headers, msg: Bytes) -> IO(Result<&1, &1, E.Error, Response>)
  server_stream(base_url, procedure, codec, headers, msg) -> IO(Result<&1, &1, E.Error, Response>)
  client_stream(base_url, procedure, codec, headers, msgs: List<&1, Bytes>) -> IO(Result<&1, &1, E.Error, Response>)
  (stream errors arrive in the EndStream; transport failures map to Unavailable; non-200 unary maps via E.from_http)
