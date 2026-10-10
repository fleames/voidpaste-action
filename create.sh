#!/usr/bin/env bash
# Create a paste via POST /api/v1/pastes. Used by action.yml (composite).
set -euo pipefail

API_BASE="${VP_API_BASE:-https://voidpaste.com}"
API_BASE="${API_BASE%/}"

if [[ -z "${VP_API_KEY:-}" ]]; then
  echo "::error::api-key is required (store as a GitHub Actions secret)"
  exit 1
fi
echo "::add-mask::${VP_API_KEY}"
if [[ -n "${VP_PASSWORD:-}" ]]; then
  echo "::add-mask::${VP_PASSWORD}"
fi

if [[ -n "${VP_PATH:-}" && -n "${VP_CONTENT:-}" ]]; then
  echo "::error::Provide either path or content, not both"
  exit 1
fi

BODY_FILE="$(mktemp)"
RESP_FILE="$(mktemp)"
CONTENT_FILE=""
trap 'rm -f "$BODY_FILE" "$RESP_FILE" ${CONTENT_FILE:+"$CONTENT_FILE"}' EXIT

if [[ -n "${VP_PATH:-}" ]]; then
  if [[ ! -f "$VP_PATH" ]]; then
    echo "::error::File not found: $VP_PATH"
    exit 1
  fi
  SIZE="$(wc -c <"$VP_PATH" | tr -d ' ')"
  if [[ "$SIZE" -gt 5242880 ]]; then
    echo "::error::File exceeds 5 MB paste limit ($SIZE bytes)"
    exit 1
  fi
  if [[ "$SIZE" -eq 0 ]]; then
    echo "::error::File is empty"
    exit 1
  fi
  CONTENT_SRC="$VP_PATH"
elif [[ -n "${VP_CONTENT:-}" ]]; then
  CONTENT_FILE="$(mktemp)"
  printf '%s' "$VP_CONTENT" >"$CONTENT_FILE"
  CONTENT_SRC="$CONTENT_FILE"
else
  echo "::error::Provide content or path"
  exit 1
fi

python3 - "$CONTENT_SRC" <<'PY' >"$BODY_FILE"
import json, os, sys
path = sys.argv[1]
with open(path, "rb") as f:
    raw = f.read()
try:
    content = raw.decode("utf-8")
except UnicodeDecodeError:
    content = raw.decode("utf-8", errors="replace")
body = {"content": content}
body["visibility"] = os.environ.get("VP_VISIBILITY") or "unlisted"
if os.environ.get("VP_TITLE"):
    body["title"] = os.environ["VP_TITLE"]
if os.environ.get("VP_LANGUAGE"):
    body["language"] = os.environ["VP_LANGUAGE"]
if os.environ.get("VP_EXPIRATION"):
    body["expiration"] = os.environ["VP_EXPIRATION"]
if os.environ.get("VP_PASSWORD"):
    body["password"] = os.environ["VP_PASSWORD"]
burn = (os.environ.get("VP_BURN") or "false").lower() in ("1", "true", "yes")
if burn:
    body["burn_after_reading"] = True
json.dump(body, sys.stdout)
PY

CURL_ARGS=(
  -sS
  -X POST
  "${API_BASE}/api/v1/pastes"
  -H "Authorization: Bearer ${VP_API_KEY}"
  -H "Content-Type: application/json"
  -H "Accept: application/json"
  -H "X-VoidPaste-Client: action"
  -H "User-Agent: voidpaste-action/1.0.1"
  --data-binary @"$BODY_FILE"
  -o "$RESP_FILE"
  -w "%{http_code}"
)

if [[ -n "${VP_IDEMPOTENCY_KEY:-}" ]]; then
  CURL_ARGS+=(-H "Idempotency-Key: ${VP_IDEMPOTENCY_KEY}")
fi

HTTP_CODE="$(curl "${CURL_ARGS[@]}")"

if [[ "$HTTP_CODE" != "201" ]]; then
  echo "::error::Create failed (HTTP ${HTTP_CODE})"
  echo "::group::Response body"
  cat "$RESP_FILE" || true
  echo
  echo "::endgroup::"
  exit 1
fi

OUT_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$RESP_FILE" "$OUT_FILE" ${CONTENT_FILE:+"$CONTENT_FILE"}' EXIT

python3 - "$RESP_FILE" "$API_BASE" "$OUT_FILE" <<'PY'
import json, os, sys

resp_path, base, out_path = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3]
with open(resp_path, encoding="utf-8") as f:
    data = json.load(f)
paste = data.get("paste") or {}
pid = paste.get("id") or ""
if not pid:
    print("::error::Response missing paste.id", file=sys.stderr)
    raise SystemExit(1)
url = f"{base}/p/{pid}"
raw = f"{base}/raw/{pid}"
warnings = data.get("warnings")

def write_output(name: str, value: str) -> None:
    gh = os.environ.get("GITHUB_OUTPUT")
    if not gh:
        return
    with open(gh, "a", encoding="utf-8") as f:
        f.write(f"{name}={value}\n")

write_output("id", pid)
write_output("url", url)
write_output("raw_url", raw)

with open(out_path, "w", encoding="utf-8") as f:
    json.dump({"id": pid, "url": url, "raw_url": raw, "warnings": warnings}, f)

if warnings:
    print(f"::warning::Secret detection warnings: {json.dumps(warnings)}")
print(f"Created {url}")
PY

ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$OUT_FILE")"
URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$OUT_FILE")"
RAW="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["raw_url"])' "$OUT_FILE")"
WARNINGS="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("warnings")))' "$OUT_FILE")"

{
  echo "## VoidPaste"
  echo
  echo "- **URL:** ${URL}"
  echo "- **ID:** \`${ID}\`"
  echo "- **Raw:** ${RAW} _(do not post raw links for burn pastes into Slack/Discord)_"
  if [[ "${WARNINGS}" != "null" && "${WARNINGS}" != "[]" ]]; then
    echo
    echo "### Warnings"
    echo
    echo '```json'
    echo "${WARNINGS}"
    echo '```'
  fi
} >>"${GITHUB_STEP_SUMMARY}"
