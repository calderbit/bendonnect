# The laws of Bendonette: facts about the Connect protocol implementation that
# must always hold. Each is proven in PROOF.bend; `bend PROOF.bend` is the gate.
import Base
import ./src/code.bend as Code
import ./src/b64.bend as B64
import ./src/error.bend as E
import ./src/metadata.bend as Md
import ./src/envelope.bend as Env
import ./src/protocol.bend as P

# A code's wire name parses back to the same code.
law code_roundtrip:
  for c: Code.Code
  {Code.from_string(Code.to_string(c)) == Some{c} : Maybe<&2, Code.Code>}

# No error code is ever sent as HTTP 200: a unary error response is never
# mistaken for a success by a plain HTTP client.
law code_http_not_ok:
  for c: Code.Code
  {U32.is_eq(Code.to_http(c), 200) == False{} : Bool}

# --- Error model, base64 and metadata ---

# The "trailer-" prefix never changes whether a key is made of legal chars,
# so a valid trailer key stays valid after trailers_to_headers prefixes it.
law trailer_prefix_keeps_key_chars:
  for +k: String
  {Md.key_chars(String.append("trailer-", k)) == Md.key_chars(k) : Bool}

# Empty keys are never valid; the legal alphabet excludes uppercase and ':'.
law valid_key_rejects_empty:
  {Md.valid_key("") == False{} : Bool}

# Alphabet translation in b64.decode (url -> std) never changes the length,
# so the padding computation done afterwards sees the true input length.
law swap2_keeps_length:
  for +s: String
  for +a1: U32
  for +b1: U32
  for +a2: U32
  for +b2: U32
  {String.length(B64.swap2(s, a1, b1, a2, b2)) == String.length(s) : Nat}

# An error code survives the trip through its JSON "code" value
# (the wire name is UTF-8 encoded then decoded back to the same code).
law code_survives_json:
  for c: Code.Code
  {E.code_of(Some{E.str_val(Code.to_string(c))}) == Some{c} : Maybe<&2, Code.Code>}

# --- Envelopes and protocol negotiation ---

# Methods other than POST and GET.
type Other is Data:
  Put{}
  Delete{}
  Patch{}
  Head{}
  Options{}

def other_name(o: Other) -> String:
  match o:
    case Put{}:
      "PUT"
    case Delete{}:
      "DELETE"
    case Patch{}:
      "PATCH"
    case Head{}:
      "HEAD"
    case Options{}:
      "OPTIONS"

# Any request with a method that is neither POST nor GET is rejected with 405,
# whatever its path, query, headers or prefix.
law other_methods_405:
  for o: Other
  for path: String
  for query: String
  for headers: Map<&2, List<&2, String>>
  for prefix: String
  {P.classify(other_name(o), path, query, headers, prefix) == Fail{P.Status{405, "method not allowed: want POST or GET"}} : Result<&2, &1, P.Reject, P.Spec>}

# The content type we emit for a standard codec parses back to the same kind and codec.
law content_type_roundtrip_json:
  for stream: Bool
  {P.parse_content_type(P.content_type(stream, P.Json{})) == Some{P.Ct{stream, P.Json{}}} : Maybe<&2, P.Ct>}

law content_type_roundtrip_proto:
  for stream: Bool
  {P.parse_content_type(P.content_type(stream, P.Proto{})) == Some{P.Ct{stream, P.Proto{}}} : Maybe<&2, P.Ct>}

# The compressed and end-stream envelope flags are distinct single bits.
law flags_disjoint:
  {U32.and(Env.flag_compressed(), Env.flag_end()) == 0 : U32}

# Timeouts that overflow 32 bits are clamped, not wrapped.
law timeout_clamps:
  {P.parse_timeout("9999999999") == Some{4294967295} : Maybe<&2, U32>}
