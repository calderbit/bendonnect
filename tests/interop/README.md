# Bendonette Go interop harness

Tests a Bendonette (Bend) Connect server against connect-go. No codegen: messages are
`wrapperspb` well-known types on service `bendonette.test.v1.TestService`.

## Run

    cd tests/interop
    go run ./server -addr 127.0.0.1:8788          # reference server (connect-go, HTTP/1.1 + h2c)
    go run ./client -url http://127.0.0.1:8788    # self-test against the reference
    go run ./client -url http://127.0.0.1:8787    # target (Bendonette)
    go run ./client -url ... -run fail/not_found -v   # filter + verbose dumps
    go run ./client -url ... -lenient             # skip [spec] cases (none currently)
    URL=http://127.0.0.1:8787 ./curl_smoke.sh

Client prints `PASS name` / `FAIL name: details`, then `SUMMARY`; exit 1 on any failure.

## Service
- Echo(StringValue)->StringValue, NO_SIDE_EFFECTS (GET ok); `x-test` request header -> `x-echo` response header; trailer `x-trail: done`.
- Fail(StringValue code name)->error with that code, message `requested failure`, detail google.protobuf.StringValue "detail".
- Count(UInt32Value n)->stream "1".."n"; trailer `x-count`=n; n==0 -> out_of_range.
- Concat(stream StringValue)->StringValue joined by a space.

## Cases (json and proto each unless noted)
echo/post, echo/headers-trailers, echo/get, fail/<code> (all 16), count/3, count/0, concat/abc, concat/empty.
Raw HTTP: unknown-procedure-404, wrong-content-type-415 (text/plain), unsupported-content-encoding-501
(zstd, body code unimplemented), protocol-version-2-400, timeout-invalid-400 (invalid_argument), json-post-wire
(200, JSON body, `Trailer-X-Trail`). Streaming content-types on unary procedures are skipped (implementation-defined).
