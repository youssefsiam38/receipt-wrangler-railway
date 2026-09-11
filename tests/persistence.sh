#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: the admin password, a receipt with its image, and settings survive container
# recreation; the bootstrap is idempotent and never resets a password the owner changed.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077; printf '%s' 'local-test-only-admin-password' > "$TEST_TMP/pw"

section "fresh stack"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --no-build; api_ready 420 || die "not ready"

section "write state"
JAR="$TEST_TMP/jar"; login admin "$TEST_TMP/pw" "$JAR" || die "login failed"
G=$(default_group "$JAR")
RID=$(create_receipt "$JAR" "$G" "Persist Mart receipt" "21.75"); [ -n "$RID" ] || die "receipt create failed"
png="$TEST_TMP/receipt.png"; make_receipt_png "$png"
IMG=$(upload_receipt_image "$JAR" "$png" "$RID"); [ -n "$IMG" ] || die "image upload failed"
api "$JAR" -o "$TEST_TMP/before.png" "$BASE_URL/api/receiptImage/$IMG/download"
sha_before=$(sha256sum "$TEST_TMP/before.png" | cut -d' ' -f1)
files_before=$(compose exec -T receipt-wrangler sh -c 'find /app/receipt-wrangler-api/data -type f | wc -l' | tr -d '\r')
pass "state written: receipt $RID, image $IMG, $files_before file(s) on the volume"

section "recreate containers on the same volumes"
compose down >/dev/null; compose up -d --no-build
api_ready 420 || die "not ready after recreate"
logs=$(compose logs --no-color receipt-wrangler)
assert_contains "bootstrap skipped" "admin bootstrap skipped: the generated password is already set" "$logs"
assert_not_contains "upstream default never used again" "signed in with upstream's default bootstrap credentials" "$logs"

section "verify"
JAR2="$TEST_TMP/jar2"
login admin "$TEST_TMP/pw" "$JAR2" && pass "admin password unchanged" || die "login failed after recreate"
assert_eq "receipt still present" "Persist Mart receipt" "$(receipt_json "$JAR2" "$RID" | jq -r .name)"
assert_eq "amount unchanged" "21.75" "$(receipt_json "$JAR2" "$RID" | jq -r .amount)"
assert_eq "line items retained" "3" "$(receipt_json "$JAR2" "$RID" | jq '.receiptItems | length')"
api "$JAR2" -o "$TEST_TMP/after.png" "$BASE_URL/api/receiptImage/$IMG/download"
assert_eq "image bytes identical" "$sha_before" "$(sha256sum "$TEST_TMP/after.png" | cut -d' ' -f1)"
files_after=$(compose exec -T receipt-wrangler sh -c 'find /app/receipt-wrangler-api/data -type f | wc -l' | tr -d '\r')
[ "$files_after" -ge "$files_before" ] && pass "volume files retained ($files_after)" || fail "files lost ($files_before -> $files_after)"

section "a password changed inside the app is not reverted by the wrapper"
NEW='changed-by-the-owner-in-app'
printf '%s' "$NEW" > "$TEST_TMP/pw2"
uid=$(api "$JAR2" "$BASE_URL/api/user/getUserClaims" | jq -r .userId)
assert_eq "password changed in app" "200" "$(api_code "$JAR2" -X POST "$BASE_URL/api/user/$uid/resetPassword" -H 'Content-Type: application/json' --data "$(jq -nc --arg p "$NEW" '{password:$p}')")"
compose restart receipt-wrangler >/dev/null; api_ready 420 || die "not ready after restart"
JAR3="$TEST_TMP/jar3"
login admin "$TEST_TMP/pw2" "$JAR3" && pass "owner's password still works after restart" || fail "owner's password was overwritten"
code=$(login_code admin 'local-test-only-admin-password')
[ "$code" != "200" ] && pass "stale RW_ADMIN_PASSWORD not re-applied (HTTP $code)" || fail "wrapper reverted the owner's password"
assert_contains "wrapper reported the stale variable" "RW_ADMIN_PASSWORD is now stale and is ignored" "$(compose logs --no-color receipt-wrangler)"
assert_contains "wrapper still proved the default is unusable" "verified that the default admin/admin credentials are not usable" "$(compose logs --no-color receipt-wrangler)"
summary
