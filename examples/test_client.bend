# Interop client: drives the Go reference server (tests/interop/server) with Cli.
#   cd tests/interop && go run ./server -addr 127.0.0.1:8788
#   bend examples/test_client.bend [http://127.0.0.1:8788]
# Messages are google.protobuf.StringValue / UInt32Value (hand-encoded; ASCII, values < 128).
import Base
import bend-kit-http@0.36.0.0/http.bend as Http
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ../src/code.bend as Code
import ../src/error.bend as E
import ../src/protocol.bend as P
import ../src/transport/client.bend as Cli

def svc() -> String:
  "bendonnect.test.v1.TestService/"

def chr(n: U32) -> String:
  SCon{Chr{n}, SNil{}}

# ---------------------------------------------------------------- wire messages

def str_msg(+codec: P.Codec, +s: String) -> Bytes.Bytes:
  match codec:
    case P.Json{}:
      Bytes.from_string("\"" ++ s ++ "\"")
    case P.Proto{}:
      Bytes.from_string(chr(10) ++ chr(U32.from_nat(String.length(s))) ++ s)
    case P.Custom{n}:
      Bytes.new(0)

def u32_msg(+codec: P.Codec, n: U32) -> Bytes.Bytes:
  match codec:
    case P.Json{}:
      Bytes.from_string(U32.show(n))
    case P.Proto{}:
      Bytes.from_string(chr(8) ++ chr(n))
    case P.Custom{x}:
      Bytes.new(0)

def drop2(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{a, t}:
      match t:
        case SNil{}:
          ""
        case SCon{b, r}:
          r

def drop1(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{a, t}:
      t

def unquote(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{a, t}:
      String.reverse(drop1(String.reverse(t)))

def str_of(+codec: P.Codec, b: Bytes.Bytes) -> String:
  match codec:
    case P.Json{}:
      unquote(Bytes.to_string(b))
    case P.Proto{}:
      drop2(Bytes.to_string(b))
    case P.Custom{n}:
      "?"

def join(+codec: P.Codec, ms: List<&1, Bytes.Bytes>, +sep: String) -> String:
  match ms:
    case Nil{}:
      ""
    case Con{h, t}:
      match t:
        case Nil{}:
          str_of(codec, h)
        case Con{h2, t2}:
          str_of(codec, h) ++ sep ++ join(codec, Con{h2, t2}, sep)

# ---------------------------------------------------------------- checks (return "" when fine)

def unexpected(e: E.Error) -> String:
  E.Error{code, message, details} = e
  "unexpected error " ++ Code.to_string(code) ++ ": " ++ message

def want_str(+want: String, +got: String) -> String:
  Bool.pick(String, String.eq(want, got), "", "want '" ++ want ++ "' got '" ++ got ++ "'")

def body_check(+codec: P.Codec, want: String, resp: Cli.Response) -> String:
  Cli.Response{h, t, ms} = resp
  want_str(want, join(codec, ms, ","))

def ok_body(+codec: P.Codec, want: String, r: Result<&1, &1, E.Error, Cli.Response>) -> String:
  match r:
    case Fail{e}:
      unexpected(e)
    case Done{resp}:
      body_check(codec, want, resp)

def body_check_ms(+codec: P.Codec, want: String, ms: List<&1, Bytes.Bytes>) -> String:
  want_str(want, join(codec, ms, ","))

# first non-empty problem
def first(+a: String, b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, a)

def meta_check(+codec: P.Codec, want: String, hk: String, hv: String, tk: String, tv: String, resp: Cli.Response) -> String:
  Cli.Response{+h, +t, ms} = resp
  first(body_check_ms(codec, want, ms), first(want_str(hv, Http.header(h, hk)), want_str(tv, Http.header(t, tk))))

def ok_meta(+codec: P.Codec, want: String, hk: String, hv: String, tk: String, tv: String, r: Result<&1, &1, E.Error, Cli.Response>) -> String:
  match r:
    case Fail{e}:
      unexpected(e)
    case Done{resp}:
      meta_check(codec, want, hk, hv, tk, tv, resp)

def detail_check(details: List<&1, E.Detail>) -> String:
  match details:
    case Nil{}:
      "no error details"
    case Con{d, rest}:
      E.Detail{type_name, value, debug} = d
      want_str("google.protobuf.StringValue", type_name)

def err_check(code: Code.Code, rest_ok: Bool, e: E.Error) -> String:
  E.Error{c, message, details} = e
  first(want_str(Code.to_string(code), Code.to_string(c)),
    first(want_str("requested failure", message), detail_check(details)))

def want_fail(code: Code.Code, r: Result<&1, &1, E.Error, Cli.Response>) -> String:
  match r:
    case Done{resp}:
      "expected an error, got success"
    case Fail{e}:
      err_check(code, True{}, e)

def want_code(code: Code.Code, r: Result<&1, &1, E.Error, Cli.Response>) -> String:
  match r:
    case Done{resp}:
      "expected an error, got success"
    case Fail{e}:
      E.Error{c, message, details} = e
      want_str(Code.to_string(code), Code.to_string(c))

# ---------------------------------------------------------------- reporting

def report.go(name: String, why: String, ok: Bool) -> IO(U32):
  match ok:
    case True{}:
      do IO<U32>:
        IO.print("PASS " ++ name)
        return 0
    case False{}:
      do IO<U32>:
        IO.print("FAIL " ++ name ++ ": " ++ why)
        return 1

def report(name: String, +why: String) -> IO(U32):
  report.go(name, why, String.is_empty(why))

def tag(+codec: P.Codec, s: String) -> String:
  P.codec_name(codec) ++ "/" ++ s

def show_len(r: Bytes.Bytes & U32) -> IO(Unit):
  (b, n) = r
  IO.print("  (each) message of " ++ U32.show(n) ++ " bytes")

def show_msg(m: Bytes.Bytes) -> IO(Unit):
  show_len(Bytes.length(m))

# ---------------------------------------------------------------- cases

def echo.post(url: String, +codec: P.Codec) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.unary(url, svc() ++ "Echo", codec, Http.empty(), str_msg(codec, "hello"))
    report(tag(codec, "echo/post"), ok_body(codec, "hello", r))

def echo.headers(url: String, +codec: P.Codec) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.unary(url, svc() ++ "Echo", codec, Http.set(Http.empty(), "x-test", "hi"), str_msg(codec, "hello"))
    report(tag(codec, "echo/headers-trailers"), ok_meta(codec, "hello", "x-echo", "hi", "x-trail", "done", r))

def echo.get(url: String, +codec: P.Codec) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.get(url, svc() ++ "Echo", codec, Http.empty(), str_msg(codec, "hello get"))
    report(tag(codec, "echo/get"), ok_body(codec, "hello get", r))

def fail.one(url: String, +codec: P.Codec, +name: String, code: Code.Code) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.unary(url, svc() ++ "Fail", codec, Http.empty(), str_msg(codec, name))
    report(tag(codec, "fail/" ++ name), want_fail(code, r))

def count.three(url: String, +codec: P.Codec) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.server_stream(url, svc() ++ "Count", codec, Http.empty(), u32_msg(codec, 3))
    report(tag(codec, "count/3"), ok_meta(codec, "1,2,3", "content-type", P.stream_content_type(codec), "x-count", "3", r))

def count.zero(url: String, +codec: P.Codec) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.server_stream(url, svc() ++ "Count", codec, Http.empty(), u32_msg(codec, 0))
    report(tag(codec, "count/0"), want_code(Code.OutOfRange{}, r))

def count.each(url: String, +codec: P.Codec) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.server_stream.each(~show_msg, url, svc() ++ "Count", codec, Http.empty(), u32_msg(codec, 3))
    report(tag(codec, "count/each"), ok_body(codec, "", r))

def concat.abc(url: String, +codec: P.Codec) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, E.Error, Cli.Response> <- Cli.client_stream(url, svc() ++ "Concat", codec, Http.empty(), [str_msg(codec, "a"), str_msg(codec, "b"), str_msg(codec, "c")])
    report(tag(codec, "concat/abc"), ok_body(codec, "a b c", r))

def suite(+url: String, +codec: P.Codec) -> IO(U32):
  do IO<U32>:
    a : U32 <- echo.post(url, codec)
    b : U32 <- echo.headers(url, codec)
    c : U32 <- echo.get(url, codec)
    d : U32 <- fail.one(url, codec, "not_found", Code.NotFound{})
    e : U32 <- fail.one(url, codec, "unavailable", Code.Unavailable{})
    f : U32 <- fail.one(url, codec, "data_loss", Code.DataLoss{})
    g : U32 <- count.three(url, codec)
    h : U32 <- count.zero(url, codec)
    i : U32 <- count.each(url, codec)
    j : U32 <- concat.abc(url, codec)
    return (a + b + c + d + e + f + g + h + i + j : U32)

def finish.go(failed: U32, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("SUMMARY all passed")
    case False{}:
      do IO<Unit>:
        IO.print("SUMMARY " ++ U32.show(failed) ++ " failed")
        IO.exit(1)

def finish(+failed: U32) -> IO(Unit):
  finish.go(failed, U32.is_zero(failed))

def url_of(args: List<&1, String>) -> String:
  match args:
    case Nil{}:
      "http://127.0.0.1:8788"
    case Con{prog, rest}:
      match rest:
        case Nil{}:
          "http://127.0.0.1:8788"
        case Con{u, more}:
          u

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1, String> <- IO.args()
    +url : String = url_of(args)
    jf : U32 <- suite(url, P.Json{})
    pf : U32 <- suite(url, P.Proto{})
    finish((jf + pf : U32))
