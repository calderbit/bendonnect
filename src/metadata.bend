# Header / trailer metadata helpers. Pure.
# Metadata maps are Map<&2, List<&2, String>> with lowercase keys.
import Base

def trailer_prefix() -> String:
  "trailer-"

def trailers_to_headers.go(xs: List<&2, Sigma<&2, &2, String, _ => List<&2, String>>>, acc: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match xs:
    case Nil{}:
      acc
    case Con{Tuple{k, v}, rest}:
      trailers_to_headers.go(rest, Map.set(&2, List<&2, String>, acc, String.append(trailer_prefix(), k), v))

# Every key gets the "trailer-" prefix (unary responses carry trailers as headers).
def trailers_to_headers(m: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  trailers_to_headers.go(Map.to_list(&2, List<&2, String>, m), Map.new(&2, List<&2, String>))

# Adds k (with prefix stripped when want) when its prefix status equals want.
def bool_eq(a: Bool, +b: Bool) -> Bool:
  Bool.pick(Bool, a, b, Bool.not(b))

def split.add(take: Bool, +want: Bool, +k: String, v: List<&2, String>, acc: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match take:
    case False{}:
      acc
    case True{}:
      Map.set(&2, List<&2, String>, acc, Bool.pick(String, want, String.drop(k, 8n), k), v)

def split.go(xs: List<&2, Sigma<&2, &2, String, _ => List<&2, String>>>, +want: Bool, acc: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match xs:
    case Nil{}:
      acc
    case Con{Tuple{+k, v}, rest}:
      split.go(rest, want, split.add(bool_eq(String.starts_with(k, trailer_prefix()), want), want, k, v, acc))

# (non-trailer headers, trailers with the "trailer-" prefix stripped)
def split_trailers(h: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>> & Map<&2, List<&2, String>>:
  +l = Map.to_list(&2, List<&2, String>, h)
  (split.go(l, False{}, Map.new(&2, List<&2, String>)), split.go(l, True{}, Map.new(&2, List<&2, String>)))

# Keys starting with "connect-" belong to the protocol.
def is_reserved(+key: String) -> Bool:
  String.starts_with(key, "connect-")

# Keys ending in "-bin" carry base64 values.
def is_binary(+key: String) -> Bool:
  String.ends_with(key, "-bin")

def key_char(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)),
  Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)),
  Bool.or(U32.is_eq(c, 95), Bool.or(U32.is_eq(c, 46), U32.is_eq(c, 45)))))

def key_chars(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(key_char(c), key_chars(t))

# 1*[0-9a-z_.-]
def valid_key(+key: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(key)), key_chars(key))
