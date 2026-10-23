import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ../src/b64.bend as B64

def check(name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      String.append("PASS ", name)
    case False{}:
      String.append("FAIL ", name)

def dec_is.some(b: Bytes.Bytes, +expect: String) -> Bool:
  String.eq(Bytes.to_string(b), expect)

def dec_is.go(m: Maybe<&1, Bytes.Bytes>, +expect: String) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{b}:
      dec_is.some(b, expect)

# decode(s) is Some(bytes whose string is expect)
def dec_is(+s: String, +expect: String) -> Bool:
  dec_is.go(B64.decode(s), expect)

def dec_none.go(m: Maybe<&1, Bytes.Bytes>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{b}:
      False{}

def dec_none(+s: String) -> Bool:
  dec_none.go(B64.decode(s))

def std(+s: String) -> String:
  B64.encode_std(Bytes.from_string(s))

def raw(+s: String) -> String:
  B64.encode_std_raw(Bytes.from_string(s))

# bytes 0xfb 0xff 0xbf: std "+/+/", url "-_-_"
def hi_str() -> String:
  SCon{Chr{251}, SCon{Chr{255}, SCon{Chr{191}, SNil{}}}}

def hi_bytes() -> Bytes.Bytes:
  Bytes.from_string(hi_str())

def main() -> List<&2, String>:
  [
    check("std ''", String.eq(std(""), "")),
    check("std f", String.eq(std("f"), "Zg==")),
    check("std fo", String.eq(std("fo"), "Zm8=")),
    check("std foo", String.eq(std("foo"), "Zm9v")),
    check("std foob", String.eq(std("foob"), "Zm9vYg==")),
    check("std fooba", String.eq(std("fooba"), "Zm9vYmE=")),
    check("std foobar", String.eq(std("foobar"), "Zm9vYmFy")),
    check("raw f", String.eq(raw("f"), "Zg")),
    check("raw fo", String.eq(raw("fo"), "Zm8")),
    check("raw foob", String.eq(raw("foob"), "Zm9vYg")),
    check("raw fooba", String.eq(raw("fooba"), "Zm9vYmE")),
    check("raw foobar", String.eq(raw("foobar"), "Zm9vYmFy")),
    check("std alphabet + /", String.eq(B64.encode_std(hi_bytes()), "+/+/")),
    check("url alphabet - _", String.eq(B64.encode_url_raw(hi_bytes()), "-_-_")),
    check("url raw f", String.eq(B64.encode_url_raw(Bytes.from_string("f")), "Zg")),
    check("dec ''", dec_is("", "")),
    check("dec padded f", dec_is("Zg==", "f")),
    check("dec unpadded f", dec_is("Zg", "f")),
    check("dec padded fo", dec_is("Zm8=", "fo")),
    check("dec unpadded fo", dec_is("Zm8", "fo")),
    check("dec foo", dec_is("Zm9v", "foo")),
    check("dec foob padded", dec_is("Zm9vYg==", "foob")),
    check("dec foob raw", dec_is("Zm9vYg", "foob")),
    check("dec fooba raw", dec_is("Zm9vYmE", "fooba")),
    check("dec foobar", dec_is("Zm9vYmFy", "foobar")),
    check("dec url alphabet", dec_is("-_-_", hi_str())),
    check("dec std alphabet", dec_is("+/+/", hi_str())),
    check("dec bad char", dec_none("Zm9v!A==")),
    check("dec bad len 1", dec_none("Z")),
    check("dec bad len 5 raw", dec_none("Zm9vY")),
    check("dec bad pad count", dec_none("Zg===")),
    check("dec wrong pad", dec_none("Zg=")),
    check("dec pad in middle", dec_none("Zg==Zg=="))
  ]
