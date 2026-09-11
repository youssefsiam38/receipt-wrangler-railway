#!/usr/bin/env bash
# shellcheck disable=SC2015
# Public smoke test against a deployed instance.
#   tests/railway-smoke.sh https://your-app.up.railway.app
# Optional login + workflow: ADMIN_USERNAME=admin ADMIN_PASSWORD_FILE=/path/to/file
#   STATE_OUT=/path/state.json (create a receipt) / STATE_IN=/path/state.json (verify after redeploy)
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
BASE_URL=${1:?usage: railway-smoke.sh https://domain}; BASE_URL=${BASE_URL%/}; export BASE_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
host=${BASE_URL#https://}

section "TLS and redirects"
assert_eq "https web UI" "200" "$(http_code "$BASE_URL/")"
assert_contains "valid certificate" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$BASE_URL/" 2>&1 || true)"
assert_contains "http -> https" "https://$host" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "http://$host/")"

section "readiness and first-run safety"
body=$(curl -s --max-time 30 "$BASE_URL/")
assert_contains "web app served" "Receipt Wrangler" "$body"
assert_not_contains "not a packaged default page" "Welcome to nginx" "$body"
assert_eq "healthcheck path (API through nginx)" "200" "$(http_code "$BASE_URL/api/featureConfig")"
assert_eq "local signup disabled" "false" "$(curl -s "$BASE_URL/api/featureConfig" | jq -r '.enableLocalSignUp')"
code=$(login_code admin admin)
[ "$code" != "200" ] && pass "upstream default admin/admin rejected (HTTP $code)" || fail "DEFAULT CREDENTIALS ACCEPTED on a public deployment"
assert_eq "unauthenticated API refused" "403" "$(http_code "$BASE_URL/api/user")"

section "cookies"
if [ -n "${ADMIN_PASSWORD_FILE:-}" ]; then
  JAR="$TEST_TMP/jar"
  login "${ADMIN_USERNAME:-admin}" "$ADMIN_PASSWORD_FILE" "$JAR" && pass "admin login with the generated password" || die "login failed"
  hdrs=$(curl -s -D - -o /dev/null -X POST "$BASE_URL/api/login" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg u "${ADMIN_USERNAME:-admin}" --rawfile p "$ADMIN_PASSWORD_FILE" '{username:$u,password:($p|rtrimstr("\n"))}')")
  assert_contains "session cookie is HttpOnly" "HttpOnly" "$hdrs"
  assert_contains "claims returned" '"username"' "$(api "$JAR" "$BASE_URL/api/user/getUserClaims")"

  if [ -n "${STATE_OUT:-}" ]; then
    section "create a receipt with a synthetic image"
    G=$(default_group "$JAR"); [ -n "$G" ] && pass "default group ($G)" || die "no group"
    RID=$(create_receipt "$JAR" "$G" "Railway Test Mart" "13.50"); [ -n "$RID" ] && pass "receipt created ($RID)" || die "receipt create failed"
    CID=$(create_category "$JAR" "Groceries-$RANDOM"); assert_eq "receipt categorized" "200" "$(categorize "$JAR" "$RID" "$CID" "Groceries")"
    png="$TEST_TMP/receipt.png"; make_receipt_png "$png"
    IMG=$(upload_receipt_image "$JAR" "$png" "$RID"); [ -n "$IMG" ] && pass "receipt image uploaded ($IMG)" || die "image upload failed"
    api "$JAR" -o "$TEST_TMP/img.png" "$BASE_URL/api/receiptImage/$IMG/download"
    jq -n --arg r "$RID" --arg i "$IMG" --arg n "Railway Test Mart" --arg s "$(sha256sum "$TEST_TMP/img.png" | cut -d' ' -f1)" \
      '{receipt:$r, image:$i, name:$n, sha:$s}' > "$STATE_OUT"; pass "state written"
  fi
  if [ -n "${STATE_IN:-}" ]; then
    section "verify state after redeploy"
    R=$(jq -r .receipt "$STATE_IN"); I=$(jq -r .image "$STATE_IN")
    assert_eq "receipt still present" "$(jq -r .name "$STATE_IN")" "$(receipt_json "$JAR" "$R" | jq -r .name)"
    assert_eq "category retained" "1" "$(receipt_json "$JAR" "$R" | jq '.categories | length')"
    assert_eq "line items retained" "3" "$(receipt_json "$JAR" "$R" | jq '.receiptItems | length')"
    api "$JAR" -o "$TEST_TMP/img2.png" "$BASE_URL/api/receiptImage/$I/download"
    assert_eq "image bytes identical" "$(jq -r .sha "$STATE_IN")" "$(sha256sum "$TEST_TMP/img2.png" | cut -d' ' -f1)"
  fi
fi
summary
