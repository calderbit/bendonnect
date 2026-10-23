# Run: bend tests/envelope_test.bend   (every entry must be True)
import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ../src/envelope.bend as Env

def hex_is(b: Bytes.Bytes, s: String) -> Bool:
  String.eq(Bytes.to_hex(b), s)

def msg() -> Bytes.Bytes:
  Bytes.from_string("{\"name\": \"Buf\"}")

def msg_hex() -> String:
  "7b226e616d65223a2022427566227d"

def env(+flags: U32, data: Bytes.Bytes) -> Env.Envelope:
  Env.Envelope{flags, data}

def two() -> Bytes.Bytes:
  Env.encode_all([env(0, msg()), env(2, Bytes.from_string("{}"))])

def first.of(r: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  (a, c) = r
  c

# The first n bytes of b.
def take(b: Bytes.Bytes, +n: U32) -> Bytes.Bytes:
  first.of(Bytes.slice(b, 0, n))

def len.of(r: Bytes.Bytes & U32) -> U32:
  (b, n) = r
  n

def show_step(s: Env.Step) -> String:
  match s:
    case Env.Need{b}:
      "need:" ++ U32.show(len.of(Bytes.length(b)))
    case Env.Bad{r}:
      "bad:" ++ r
    case Env.Got{Env.Envelope{f, d}, rest}:
      "got:" ++ U32.show(f) ++ ":" ++ Bytes.to_hex(d) ++ "|" ++ Bytes.to_hex(rest)

def show_list(l: List<&1, Env.Envelope>) -> String:
  match l:
    case Nil{}:
      ""
    case Con{Env.Envelope{f, d}, t}:
      U32.show(f) ++ ":" ++ Bytes.to_hex(d) ++ ";" ++ show_list(t)

def show_all(r: Result<&2, &1, String, List<&1, Env.Envelope>>) -> String:
  match r:
    case Fail{e}:
      "fail:" ++ e
    case Done{l}:
      show_list(l)

def eq(a: String, b: String) -> Bool:
  String.eq(a, b)

def main() -> List<&2, Bool>:
  [
    # encode: exact bytes (flags 0, length 15)
    hex_is(Env.encode(env(0, msg())), "000000000f" ++ msg_hex()),
    # end-stream flag
    hex_is(Env.encode(env(Env.flag_end(), Bytes.from_string("{}"))), "02000000027b7d"),
    # compressed flag
    hex_is(Env.encode(env(Env.flag_compressed(), Bytes.from_string("{}"))), "01000000027b7d"),
    # empty message
    hex_is(Env.encode(env(0, Bytes.new(0))), "0000000000"),
    # encode_all is concatenation
    hex_is(two(), "000000000f" ++ msg_hex() ++ "02000000027b7d"),
    hex_is(Env.encode_all(Nil{}), ""),
    # decode: one envelope off a concatenation, remainder returned
    eq(show_step(Env.decode(two(), 1000)), "got:0:" ++ msg_hex() ++ "|02000000027b7d"),
    # decode_all
    eq(show_all(Env.decode_all(two(), 1000)), "0:" ++ msg_hex() ++ ";2:7b7d;"),
    eq(show_all(Env.decode_all(Bytes.new(0), 1000)), ""),
    eq(show_all(Env.decode_all(Env.encode(env(0, Bytes.new(0))), 1000)), "0:;"),
    # empty message envelope via decode
    eq(show_step(Env.decode(Env.encode(env(2, Bytes.new(0))), 0)), "got:2:|"),
    # partial buffers -> Need (buffer handed back whole)
    eq(show_step(Env.decode(Bytes.new(0), 1000)), "need:0"),
    eq(show_step(Env.decode(take(two(), 3), 1000)), "need:3"),
    eq(show_step(Env.decode(take(two(), 5), 1000)), "need:5"),
    eq(show_step(Env.decode(take(two(), 19), 1000)), "need:19"),
    # exactly complete first envelope
    eq(show_step(Env.decode(take(two(), 20), 1000)), "got:0:" ++ msg_hex() ++ "|"),
    # too large -> Bad, even before the body arrives
    eq(show_step(Env.decode(two(), 14)), "bad:message size 15 is larger than configured max 14"),
    eq(show_step(Env.decode(take(two(), 5), 10)), "bad:message size 15 is larger than configured max 10"),
    eq(show_step(Env.decode(two(), 15)), "got:0:" ++ msg_hex() ++ "|02000000027b7d"),
    # reserved bits are preserved, not rejected
    eq(show_step(Env.decode(Env.encode(env(129, Bytes.from_string("{}"))), 1000)), "got:129:7b7d|"),
    # trailing partial envelope -> Fail
    eq(show_all(Env.decode_all(take(two(), 22), 1000)), "fail:incomplete envelope at end of body"),
    eq(show_all(Env.decode_all(take(two(), 3), 1000)), "fail:incomplete envelope at end of body"),
    # oversize inside decode_all
    eq(show_all(Env.decode_all(two(), 14)), "fail:message size 15 is larger than configured max 14")
  ]
