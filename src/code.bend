# Connect error codes (https://connectrpc.com/docs/protocol/#error-codes).
# Only these sixteen codes are valid: Connect has no user-defined codes.
import Base

type Code is Data:
  Canceled{}
  Unknown{}
  InvalidArgument{}
  DeadlineExceeded{}
  NotFound{}
  AlreadyExists{}
  PermissionDenied{}
  ResourceExhausted{}
  FailedPrecondition{}
  Aborted{}
  OutOfRange{}
  Unimplemented{}
  Internal{}
  Unavailable{}
  DataLoss{}
  Unauthenticated{}

# The wire name, as it appears in an Error's "code" property.
def to_string(c: Code) -> String:
  match c:
    case Canceled{}:
      "canceled"
    case Unknown{}:
      "unknown"
    case InvalidArgument{}:
      "invalid_argument"
    case DeadlineExceeded{}:
      "deadline_exceeded"
    case NotFound{}:
      "not_found"
    case AlreadyExists{}:
      "already_exists"
    case PermissionDenied{}:
      "permission_denied"
    case ResourceExhausted{}:
      "resource_exhausted"
    case FailedPrecondition{}:
      "failed_precondition"
    case Aborted{}:
      "aborted"
    case OutOfRange{}:
      "out_of_range"
    case Unimplemented{}:
      "unimplemented"
    case Internal{}:
      "internal"
    case Unavailable{}:
      "unavailable"
    case DataLoss{}:
      "data_loss"
    case Unauthenticated{}:
      "unauthenticated"

# The HTTP status a unary error response carries.
def to_http(c: Code) -> U32:
  match c:
    case Canceled{}:
      499
    case Unknown{}:
      500
    case InvalidArgument{}:
      400
    case DeadlineExceeded{}:
      504
    case NotFound{}:
      404
    case AlreadyExists{}:
      409
    case PermissionDenied{}:
      403
    case ResourceExhausted{}:
      429
    case FailedPrecondition{}:
      400
    case Aborted{}:
      409
    case OutOfRange{}:
      400
    case Unimplemented{}:
      501
    case Internal{}:
      500
    case Unavailable{}:
      503
    case DataLoss{}:
      500
    case Unauthenticated{}:
      401

# All codes, in the order of the spec's table.
def all() -> List<&2, Code>:
  [Canceled{}, Unknown{}, InvalidArgument{}, DeadlineExceeded{}, NotFound{},
   AlreadyExists{}, PermissionDenied{}, ResourceExhausted{}, FailedPrecondition{},
   Aborted{}, OutOfRange{}, Unimplemented{}, Internal{}, Unavailable{}, DataLoss{},
   Unauthenticated{}]

def from_string.pick(hit: Bool, c: Code, rest: Unit -> Maybe<&2, Code>) -> Maybe<&2, Code>:
  match hit:
    case True{}:
      Some{c}
    case False{}:
      rest(Unit{})

def from_string.go(cs: List<&2, Code>, +s: String) -> Maybe<&2, Code>:
  match cs:
    case Nil{}:
      None{}
    case Con{+c, rest}:
      from_string.pick(String.eq(to_string(c), s), c, u => from_string.go(rest, s))

# Parses a wire name; None for anything that is not one of the sixteen codes.
def from_string(+s: String) -> Maybe<&2, Code>:
  from_string.go(all(), s)

# One row of the spec's HTTP-to-code table.
type Row is Data:
  Row{status: U32, code: Code}

def from_http.pick(hit: Bool, c: Code, rest: Unit -> Code) -> Code:
  match hit:
    case True{}:
      c
    case False{}:
      rest(Unit{})

def from_http.go(table: List<&2, Row>, +status: U32) -> Code:
  match table:
    case Nil{}:
      Unknown{}
    case Con{Row{+k, c}, rest}:
      from_http.pick(U32.is_eq(k, status), c, u => from_http.go(rest, status))

# The code a client infers from a non-200 status with no Connect error body.
def from_http(+status: U32) -> Code:
  from_http.go([Row{400, Internal{}}, Row{401, Unauthenticated{}}, Row{403, PermissionDenied{}},
    Row{404, Unimplemented{}}, Row{429, Unavailable{}}, Row{502, Unavailable{}},
    Row{503, Unavailable{}}, Row{504, Unavailable{}}], status)
