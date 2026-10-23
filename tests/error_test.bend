import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import bend-kit-encoding@0.4.0.0/encoding.bend as Enc
import bend-kit-json@0.6.1.1/json.bend as Json
import ../src/code.bend as Code
import ../src/b64.bend as B64
import ../src/error.bend as E

def check(name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      String.append("PASS ", name)
    case False{}:
      String.append("FAIL ", name)

def dbg_mark(m: Maybe<&1, Json.Val>) -> String:
  match m:
    case None{}:
      ""
    case Some{v}:
      "+dbg"

def det_sum.one(d: E.Detail, rest: String) -> String:
  E.Detail{+ty, value, debug} = d
  String.concat([ty, "=", B64.encode_std_raw(value), dbg_mark(debug), ";", rest])

def det_sum(ds: List<&1, E.Detail>) -> String:
  match ds:
    case Nil{}:
      ""
    case Con{d, t}:
      det_sum.one(d, det_sum(t))

def err_sum(e: E.Error) -> String:
  E.Error{code, +message, details} = e
  String.concat([Code.to_string(code), "|", message, "|", det_sum(details)])

def sum(m: Maybe<&1, E.Error>) -> String:
  match m:
    case None{}:
      "none"
    case Some{e}:
      err_sum(e)

def json_str(b: Bytes.Bytes) -> String:
  Enc.utf8.decode(b)

def retry_detail() -> E.Detail:
  E.Detail{"google.rpc.RetryInfo", Bytes.from_string(SCon{Chr{10}, SCon{Chr{2}, SCon{Chr{8}, SCon{Chr{60}, SNil{}}}}}), None{}}

def full_err() -> E.Error:
  E.Error{Code.Unavailable{}, "overloaded", [retry_detail()]}

def lit(+s: String) -> Bytes.Bytes:
  Enc.utf8.encode(s)

def dec(+s: String) -> String:
  sum(E.decode(lit(s)))

def from_http_sum(+status: U32, +body: String) -> String:
  err_sum(E.from_http(status, lit(body)))

# ---- end stream helpers
def md_look.fin(r: Map<&2, List<&2, String>> & Maybe<&2, List<&2, String>>) -> String:
  (m, v) = r
  match v:
    case None{}:
      "<none>"
    case Some{xs}:
      String.join(xs, ",")

def end_sum.go(e: Maybe<&1, E.Error>, md: Map<&2, List<&2, String>>, +k: String) -> String:
  String.concat([sum(e), " / ", md_look.fin(Map.pop(&2, List<&2, String>, md, k))])

def end_sum(m: Maybe<&1, E.EndStream>, +k: String) -> String:
  match m:
    case None{}:
      "none"
    case Some{E.EndStream{e, md}}:
      end_sum.go(e, md, k)

def end_dec(+s: String, +k: String) -> String:
  end_sum(E.end_decode(lit(s)), k)

def md_x() -> Map<&2, List<&2, String>>:
  Map.set(&2, List<&2, String>, Map.new(&2, List<&2, String>), "x-cost", ["237", "9"])

def end_ok() -> E.EndStream:
  E.EndStream{None{}, md_x()}

def end_err() -> E.EndStream:
  E.EndStream{Some{full_err()}, md_x()}

def end_empty() -> E.EndStream:
  E.EndStream{None{}, Map.new(&2, List<&2, String>)}

def main() -> List<&2, String>:
  [
    check("encode full", String.eq(json_str(E.encode(full_err())), "{\"code\":\"unavailable\",\"message\":\"overloaded\",\"details\":[{\"type\":\"google.rpc.RetryInfo\",\"value\":\"CgIIPA\"}]}")),
    check("encode minimal omits message/details", String.eq(json_str(E.encode(E.new(Code.NotFound{}, ""))), "{\"code\":\"not_found\"}")),
    check("roundtrip full", String.eq(sum(E.decode(E.encode(full_err()))), "unavailable|overloaded|google.rpc.RetryInfo=CgIIPA;")),
    check("roundtrip no details", String.eq(sum(E.decode(E.encode(E.new(Code.Internal{}, "boom")))), "internal|boom|")),
    check("roundtrip unicode message", String.eq(sum(E.decode(E.encode(E.new(Code.Internal{}, "héllo ✓")))), "internal|héllo ✓|")),
    check("decode with debug", String.eq(dec("{\"code\":\"unavailable\",\"message\":\"m\",\"details\":[{\"type\":\"google.rpc.RetryInfo\",\"value\":\"CgIIPA\",\"debug\":{\"retryDelay\":\"30s\"}}]}"), "unavailable|m|google.rpc.RetryInfo=CgIIPA+dbg;")),
    check("decode padded detail value", String.eq(dec("{\"code\":\"internal\",\"details\":[{\"type\":\"t\",\"value\":\"Zg==\"}]}"), "internal||t=Zg;")),
    check("decode just code", String.eq(dec("{\"code\":\"canceled\"}"), "canceled||")),
    check("decode {} rejected", String.eq(dec("{}"), "none")),
    check("decode code null rejected", String.eq(dec("{\"code\":null}"), "none")),
    check("decode code number rejected", String.eq(dec("{\"code\":5}"), "none")),
    check("decode not json rejected", String.eq(dec("<html>"), "none")),
    check("decode array rejected", String.eq(dec("[]"), "none")),
    check("decode unknown code -> unknown", String.eq(dec("{\"code\":\"bogus\",\"message\":\"x\"}"), "unknown|x|")),
    check("decode drops bad detail", String.eq(dec("{\"code\":\"internal\",\"details\":[{\"type\":\"t\"},{\"type\":\"u\",\"value\":\"!!\"},{\"type\":\"v\",\"value\":\"Zg\"}]}"), "internal||v=Zg;")),
    check("from_http parses body", String.eq(from_http_sum(503, "{\"code\":\"data_loss\",\"message\":\"x\"}"), "data_loss|x|")),
    check("from_http malformed 404", String.eq(from_http_sum(404, "oops"), "unimplemented|Not Found|")),
    check("from_http malformed 503", String.eq(from_http_sum(503, ""), "unavailable|Service Unavailable|")),
    check("from_http malformed 401", String.eq(from_http_sum(401, "x"), "unauthenticated|Unauthorized|")),
    check("from_http malformed 418", String.eq(from_http_sum(418, "{}"), "unknown|HTTP 418|")),
    check("end encode ok", String.eq(json_str(E.end_encode(end_ok())), "{\"metadata\":{\"x-cost\":[\"237\",\"9\"]}}")),
    check("end encode empty", String.eq(json_str(E.end_encode(end_empty())), "{}")),
    check("end encode error", String.eq(json_str(E.end_encode(end_err())), "{\"error\":{\"code\":\"unavailable\",\"message\":\"overloaded\",\"details\":[{\"type\":\"google.rpc.RetryInfo\",\"value\":\"CgIIPA\"}]},\"metadata\":{\"x-cost\":[\"237\",\"9\"]}}")),
    check("end roundtrip error+metadata", String.eq(end_sum(E.end_decode(E.end_encode(end_err())), "x-cost"), "unavailable|overloaded|google.rpc.RetryInfo=CgIIPA; / 237,9")),
    check("end roundtrip success+metadata", String.eq(end_sum(E.end_decode(E.end_encode(end_ok())), "x-cost"), "none / 237,9")),
    check("end decode {}", String.eq(end_dec("{}", "x"), "none / <none>")),
    check("end decode error only", String.eq(end_dec("{\"error\":{\"code\":\"unavailable\"}}", "x"), "unavailable|| / <none>")),
    check("end decode lowercases keys", String.eq(end_dec("{\"metadata\":{\"X-Cost\":[\"1\"]}}", "x-cost"), "none / 1")),
    check("end decode error null invalid", String.eq(end_dec("{\"error\":null}", "x"), "none")),
    check("end decode error {} invalid", String.eq(end_dec("{\"error\":{}}", "x"), "none")),
    check("end decode error code null invalid", String.eq(end_dec("{\"error\":{\"code\":null}}", "x"), "none")),
    check("end decode garbage", String.eq(end_dec("nope", "x"), "none"))
  ]
