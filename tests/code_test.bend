import Base
import ../src/code.bend as Code

def is_code(m: Maybe<&2, Code.Code>, +want: String) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{c}:
      String.eq(Code.to_string(c), want)

def is_none(m: Maybe<&2, Code.Code>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{c}:
      False{}

def main() -> List<&2, Bool>:
  [is_code(Code.from_string("data_loss"), "data_loss"),
   is_none(Code.from_string("nope")),
   is_none(Code.from_string("")),
   is_none(Code.from_string("Unavailable")),
   String.eq(Code.to_string(Code.from_http(400)), "internal"),
   String.eq(Code.to_string(Code.from_http(404)), "unimplemented"),
   String.eq(Code.to_string(Code.from_http(502)), "unavailable"),
   String.eq(Code.to_string(Code.from_http(418)), "unknown"),
   U32.is_eq(Code.to_http(Code.Canceled{}), 499),
   U32.is_eq(Code.to_http(Code.Unauthenticated{}), 401)]
