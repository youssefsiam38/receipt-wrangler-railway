#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for receipt-wrangler-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, lengths, and pass/fail results are printed.

: "${BASE_URL:=http://localhost:9082}"
: "${TEST_TIMEOUT:=300}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

# here-strings, not pipes: `grep -q` exits on the first match and a pipe writer would get SIGPIPE,
# which `pipefail` reports as failure when the haystack is larger than the pipe buffer
assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }
logs_match() { local l; l=$(compose logs --no-color receipt-wrangler 2>/dev/null); grep -qiE -- "$1" <<<"$l"; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url" || true)
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

# login USERNAME PASSWORD_FILE JAR -> 0 on success; leaves session cookies in JAR.
# Retries while the API is still starting behind nginx (502/504) or nginx is rate-limiting
# /api/login (503, 30 requests per minute upstream).
login() {
  local u=$1 pf=$2 jar=$3 code
  for _ in $(seq 1 20); do
    : > "$jar"
    code=$(curl -s -o /dev/null -w '%{http_code}' -c "$jar" -X POST "$BASE_URL/api/login" \
      -H 'Content-Type: application/json' --data "$(jq -nc --arg u "$u" --rawfile p "$pf" '{username:$u,password:($p|rtrimstr("\n"))}')" || true)
    [ "$code" = "200" ] && return 0
    case "$code" in 502|503|504|000) sleep 5 ;; *) return 1 ;; esac
  done
  return 1
}
# api_ready [TIMEOUT] -> waits until the Go API answers through nginx (not just the static app)
api_ready() { wait_for_code "$BASE_URL/api/featureConfig" 200 "${1:-$TEST_TIMEOUT}"; }
# login_code USERNAME PASSWORD -> HTTP status for a literal password (used for negative tests)
login_code() { http_code -X POST "$BASE_URL/api/login" -H 'Content-Type: application/json' --data "$(jq -nc --arg u "$1" --arg p "$2" '{username:$u,password:$p}')"; }
api() { local jar=$1; shift; curl -s -b "$jar" "$@"; }
api_code() { local jar=$1; shift; curl -s -o /dev/null -w '%{http_code}' -b "$jar" --max-time 60 "$@"; }

make_receipt_png() { python3 "$REPO_ROOT/tests/fixtures/make-receipt.py" "$1" >/dev/null; }

# upload_receipt_image JAR FILE RECEIPTID -> prints the created receipt image id
upload_receipt_image() {
  api "$1" -X POST "$BASE_URL/api/receiptImage" -F "receiptId=$3" -F "file=@$2;type=image/png" | jq -r '.id // empty'
}
# default_group JAR -> id of the user's first group
default_group() { api "$1" "$BASE_URL/api/group" | jq -r '(if type=="array" then . else (.data // []) end)[0].id'; }
compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }

# create_receipt JAR GROUP NAME AMOUNT -> prints receipt id
create_receipt() {
  api "$1" -X POST "$BASE_URL/api/receipt" -H 'Content-Type: application/json' \
    --data "$(jq -nc --argjson g "$2" --arg n "$3" --arg a "$4" \
      '{name:$n, amount:$a, date:"2026-01-15T00:00:00Z", groupId:$g, paidByUserId:1, status:"OPEN",
        categories:[], tags:[], comments:[], customFields:[],
        receiptItems:[{name:"Coffee", chargedToUserId:1, amount:"4.50", status:"OPEN"},
                      {name:"Bagel",  chargedToUserId:1, amount:"3.25", status:"OPEN"},
                      {name:"Juice",  chargedToUserId:1, amount:"4.75", status:"OPEN"}]}')" \
    | jq -r '.id // empty'
}
# create_category JAR NAME -> prints category id
create_category() {
  api "$1" -X POST "$BASE_URL/api/category" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg n "$2" '{name:$n, description:"synthetic test category"}')" | jq -r '.id // empty'
}
# categorize JAR RECEIPT CATEGORY_ID CATEGORY_NAME -> HTTP code of the update.
# The update endpoint validates the whole receipt, and every line item must carry its receiptId,
# so the payload is built from the receipt as stored rather than hand-written.
categorize() {
  local jar=$1 rid=$2 cid=$3 cname=$4 payload
  payload=$(receipt_json "$jar" "$rid" | jq -c --argjson cid "$cid" --arg cname "$cname" --argjson rid "$rid" '{
    name, amount, date, groupId, paidByUserId, status,
    categories: [{id: $cid, name: $cname}],
    tags: [], comments: [], customFields: [],
    receiptItems: [ (.receiptItems // [])[] | {id, name, amount, chargedToUserId, status, receiptId: $rid} ]
  }')
  api_code "$jar" -X PUT "$BASE_URL/api/receipt/$rid" -H 'Content-Type: application/json' --data "$payload"
}
receipt_json() { api "$1" "$BASE_URL/api/receipt/$2"; }
