# Proofs of every law in LAWS.bend.
import Base
import ./src/code.bend as Code
import ./src/b64.bend as B64
import ./src/error.bend as E
import ./src/metadata.bend as Md
import ./src/envelope.bend as Env
import ./src/protocol.bend as P
import ./LAWS.bend as Laws

def Laws.code_roundtrip(c):
  match c:
    case Code.Canceled{}:
      {==}
    case Code.Unknown{}:
      {==}
    case Code.InvalidArgument{}:
      {==}
    case Code.DeadlineExceeded{}:
      {==}
    case Code.NotFound{}:
      {==}
    case Code.AlreadyExists{}:
      {==}
    case Code.PermissionDenied{}:
      {==}
    case Code.ResourceExhausted{}:
      {==}
    case Code.FailedPrecondition{}:
      {==}
    case Code.Aborted{}:
      {==}
    case Code.OutOfRange{}:
      {==}
    case Code.Unimplemented{}:
      {==}
    case Code.Internal{}:
      {==}
    case Code.Unavailable{}:
      {==}
    case Code.DataLoss{}:
      {==}
    case Code.Unauthenticated{}:
      {==}

def Laws.code_http_not_ok(c):
  match c:
    case Code.Canceled{}:
      {==}
    case Code.Unknown{}:
      {==}
    case Code.InvalidArgument{}:
      {==}
    case Code.DeadlineExceeded{}:
      {==}
    case Code.NotFound{}:
      {==}
    case Code.AlreadyExists{}:
      {==}
    case Code.PermissionDenied{}:
      {==}
    case Code.ResourceExhausted{}:
      {==}
    case Code.FailedPrecondition{}:
      {==}
    case Code.Aborted{}:
      {==}
    case Code.OutOfRange{}:
      {==}
    case Code.Unimplemented{}:
      {==}
    case Code.Internal{}:
      {==}
    case Code.Unavailable{}:
      {==}
    case Code.DataLoss{}:
      {==}
    case Code.Unauthenticated{}:
      {==}

def Laws.trailer_prefix_keeps_key_chars(k):
  {==}

def Laws.valid_key_rejects_empty():
  {==}

def Laws.swap2_keeps_length(s, a1, b1, a2, b2):
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      %Laws.swap2_keeps_length(t, a1, b1, a2, b2) : {1n+String.length(B64.swap2(t, a1, b1, a2, b2)) == 1n+_ : Nat}
      {==}

def Laws.code_survives_json(c):
  match c:
    case Code.Canceled{}:
      {==}
    case Code.Unknown{}:
      {==}
    case Code.InvalidArgument{}:
      {==}
    case Code.DeadlineExceeded{}:
      {==}
    case Code.NotFound{}:
      {==}
    case Code.AlreadyExists{}:
      {==}
    case Code.PermissionDenied{}:
      {==}
    case Code.ResourceExhausted{}:
      {==}
    case Code.FailedPrecondition{}:
      {==}
    case Code.Aborted{}:
      {==}
    case Code.OutOfRange{}:
      {==}
    case Code.Unimplemented{}:
      {==}
    case Code.Internal{}:
      {==}
    case Code.Unavailable{}:
      {==}
    case Code.DataLoss{}:
      {==}
    case Code.Unauthenticated{}:
      {==}

def Laws.other_methods_405(o, path, query, headers, prefix):
  match o:
    case Laws.Put{}:
      {==}
    case Laws.Delete{}:
      {==}
    case Laws.Patch{}:
      {==}
    case Laws.Head{}:
      {==}
    case Laws.Options{}:
      {==}

def Laws.content_type_roundtrip_json(stream):
  match stream:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.content_type_roundtrip_proto(stream):
  match stream:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.flags_disjoint():
  {==}

def Laws.timeout_clamps():
  {==}
