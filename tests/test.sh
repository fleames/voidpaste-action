#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${TEST_CAPTURE:?}"
: "${TEST_RESPONSE:?}"
out=""
body=""
{
  printf '%s\n' "$@"
} >"${TEST_CAPTURE}.args"
while (($#)); do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --data-binary) body="${2#@}"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$body" "${TEST_CAPTURE}.body"
cp "$TEST_RESPONSE" "$out"
printf '201'
SH
chmod +x "$TMP/curl"

cat >"$TMP/response.json" <<'JSON'
{"paste":{"id":"Abcd1234Efgh5678Ijkl"},"warnings":[]}
JSON

export PATH="$TMP:$PATH"
export TEST_CAPTURE="$TMP/request"
export TEST_RESPONSE="$TMP/response.json"
export GITHUB_OUTPUT="$TMP/output"
export GITHUB_STEP_SUMMARY="$TMP/summary"
export VP_API_KEY="vp_test_mask_me"
export VP_API_BASE="https://voidpaste.example"
export VP_CONTENT="hello from action"
export VP_PATH=""
export VP_TITLE="CI log"
export VP_LANGUAGE="log"
export VP_VISIBILITY="unlisted"
export VP_EXPIRATION="1d"
export VP_BURN="false"
export VP_PASSWORD="password_mask_me"
export VP_IDEMPOTENCY_KEY="retry-key"

output="$(bash "$ROOT/create.sh")"

grep -Fx -- "-H" "$TMP/request.args" >/dev/null
grep -Fx -- "X-VoidPaste-Client: action" "$TMP/request.args" >/dev/null
grep -Fx -- "User-Agent: voidpaste-action/1.0.1" "$TMP/request.args" >/dev/null
grep -Fx -- "Authorization: Bearer vp_test_mask_me" "$TMP/request.args" >/dev/null
grep -Fx -- "Idempotency-Key: retry-key" "$TMP/request.args" >/dev/null

python3 - "$TMP/request.body" <<'PY'
import json, sys
body = json.load(open(sys.argv[1], encoding="utf-8"))
assert body == {
    "content": "hello from action",
    "visibility": "unlisted",
    "title": "CI log",
    "language": "log",
    "expiration": "1d",
    "password": "password_mask_me",
}
PY

grep -Fx "id=Abcd1234Efgh5678Ijkl" "$GITHUB_OUTPUT" >/dev/null
grep -Fx "url=https://voidpaste.example/p/Abcd1234Efgh5678Ijkl" "$GITHUB_OUTPUT" >/dev/null
grep -Fx "raw_url=https://voidpaste.example/raw/Abcd1234Efgh5678Ijkl" "$GITHUB_OUTPUT" >/dev/null
grep -F "::add-mask::vp_test_mask_me" <<<"$output" >/dev/null
grep -F "::add-mask::password_mask_me" <<<"$output" >/dev/null

if grep -F "vp_test_mask_me" "$GITHUB_OUTPUT" "$GITHUB_STEP_SUMMARY" >/dev/null; then
  echo "secret leaked into action outputs or summary" >&2
  exit 1
fi

echo "ACTION_TESTS_OK"
