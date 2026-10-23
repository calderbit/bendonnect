# Base64 (RFC 4648 sections 4 and 5) over Bytes. Pure.
# Encoders return String (ASCII); decode takes a String and accepts either
# alphabet, padded or not. Built on Bytes.to_base64 / Bytes.from_base64.
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Drops the leading '=' run of a reversed string (i.e. trailing pad of the original).
def strip_pad.pick(hit: Bool, h: Char, t: String, rest: Unit -> String) -> String:
  match hit:
    case True{}:
      rest(Unit{})
    case False{}:
      SCon{h, t}

def strip_pad.rev(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+c}, +t}:
      strip_pad.pick(U32.is_eq(c, 61), Chr{c}, t, u => strip_pad.rev(t))

# Maps char a1 to b1 and a2 to b2, leaving other chars alone.
def swap2(s: String, +a1: U32, +b1: U32, +a2: U32, +b2: U32) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+c}, t}:
      SCon{Chr{Bool.pick(U32, U32.is_eq(c, a1), b1, Bool.pick(U32, U32.is_eq(c, a2), b2, c))}, swap2(t, a1, b1, a2, b2)}

# Standard alphabet ('+', '/') with '=' padding.
def encode_std(b: Bytes.Bytes) -> String:
  Bytes.to_base64(b)

# Standard alphabet, no padding.
def encode_std_raw(b: Bytes.Bytes) -> String:
  String.reverse(strip_pad.rev(String.reverse(Bytes.to_base64(b))))

# URL-safe alphabet ('-', '_'), no padding.
def encode_url_raw(b: Bytes.Bytes) -> String:
  swap2(encode_std_raw(b), 43, 45, 47, 95)

def has_pad(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, t}:
      Bool.or(U32.is_eq(c, 61), has_pad(t))

def decode.padded(+s: String, +m: U32) -> Maybe<&1, Bytes.Bytes>:
  Bool.pick(Maybe<&1, Bytes.Bytes>, U32.is_eq(m, 0), Bytes.from_base64(s),
  Bool.pick(Maybe<&1, Bytes.Bytes>, U32.is_eq(m, 2), Bytes.from_base64(String.append(s, "==")),
  Bool.pick(Maybe<&1, Bytes.Bytes>, U32.is_eq(m, 3), Bytes.from_base64(String.append(s, "=")),
  None{})))

def decode.norm(+s: String, +n: U32) -> Maybe<&1, Bytes.Bytes>:
  Bool.pick(Maybe<&1, Bytes.Bytes>, has_pad(s), Bytes.from_base64(s), decode.padded(s, (n .&. 3 : U32)))

# Either alphabet, padded or unpadded. None on any invalid input (bad char,
# bad padding, impossible length).
def decode(+s: String) -> Maybe<&1, Bytes.Bytes>:
  decode.norm(swap2(s, 45, 43, 95, 47), Bytes.count(s, 0))
