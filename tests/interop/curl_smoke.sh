#!/usr/bin/env bash
# Smoke-test a Connect server with curl. Usage: URL=http://127.0.0.1:8787 ./curl_smoke.sh
URL="${URL:-http://127.0.0.1:8787}"
P=/bendonette.test.v1.TestService
set -x
# unary JSON echo
curl -si "$URL$P/Echo" -H 'Content-Type: application/json' -H 'Connect-Protocol-Version: 1' -H 'x-test: hi' -d '"hello"'
# unary GET echo (message is percent-encoded JSON)
curl -si "$URL$P/Echo?connect=v1&encoding=json&message=%22hello%22"
# unary error
curl -si "$URL$P/Fail" -H 'Content-Type: application/json' -d '"not_found"'
# server stream Count n=3: envelope = flag byte + 4-byte BE length + JSON; end frame has flag 0x02
printf '\x00\x00\x00\x00\x01' > "${TMPDIR:-/tmp}/bend_count_req.bin"; printf '3' >> "${TMPDIR:-/tmp}/bend_count_req.bin"
curl -s --raw "$URL$P/Count" -H 'Content-Type: application/connect+json' -H 'Connect-Protocol-Version: 1' \
  --data-binary @"${TMPDIR:-/tmp}/bend_count_req.bin" | xxd
