#!/usr/bin/env bash
# shellcheck disable=SC2015
# Local smoke test. Run `docker compose build` first (CI does), or set RECEIPT_WRANGLER_RAILWAY_IMAGE.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"; METRICS="$REPO_ROOT/test-output/metrics.txt"
LOCAL_ENCRYPTION_KEY='local-test-only-encryption-key-not-for-production'
LOCAL_SECRET_KEY='local-test-only-secret-key-not-for-production'
LOCAL_ADMIN_PASSWORD='local-test-only-admin-password'
LOCAL_DB_PASSWORD='local-test-only-db-password'
umask 077; printf '%s' "$LOCAL_ADMIN_PASSWORD" > "$TEST_TMP/pw"

section "fresh stack (empty volumes)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/" 200 420 && pass "web UI served" || { compose logs --no-color receipt-wrangler | tail -40; die "web UI never served"; }
api_ready 420 && pass "API answering through nginx" || { compose logs --no-color receipt-wrangler | tail -40; die "API never became ready"; }
cold=$(( $(date +%s) - t0 )); echo "cold_start_seconds=$cold" | tee "$METRICS"

section "first-boot admin bootstrap"
logs=$(compose logs --no-color receipt-wrangler)
assert_contains "pre-start phase (nginx down)" "launching the API alone (nginx stays down)" "$logs"
assert_contains "signed in with upstream default" "signed in with upstream's default bootstrap credentials" "$logs"
assert_contains "bootstrap complete" "admin bootstrap complete" "$logs"
assert_contains "public start" "starting Receipt Wrangler: API on 8081, nginx on" "$logs"
assert_contains "nginx logs to stderr" "nginx/1" "$logs"
for sec in "$LOCAL_ENCRYPTION_KEY" "$LOCAL_SECRET_KEY" "$LOCAL_ADMIN_PASSWORD" "$LOCAL_DB_PASSWORD"; do
  assert_not_contains "secret not in logs (len ${#sec})" "$sec" "$logs"
done

section "default credentials are not usable"
code=$(login_code admin admin)
[ "$code" != "200" ] && pass "upstream default admin/admin rejected (HTTP $code)" || fail "admin/admin still works"
assert_eq "unauthenticated API refused" "403" "$(http_code "$BASE_URL/api/user")"
assert_eq "system settings refused" "403" "$(http_code "$BASE_URL/api/systemSettings")"

section "sign in with the generated password"
JAR="$TEST_TMP/jar"
login admin "$TEST_TMP/pw" "$JAR" && pass "admin login" || die "admin login failed"
me=$(api "$JAR" "$BASE_URL/api/user/getUserClaims")
assert_contains "claims are for admin" '"username":"admin"' "$me"
assert_eq "local signup disabled by default" "false" "$(curl -s "$BASE_URL/api/featureConfig" | jq -r '.enableLocalSignUp')"

section "core workflow: receipt, items, category, image"
G=$(default_group "$JAR"); [ -n "$G" ] && [ "$G" != "null" ] && pass "default group ($G)" || die "no group"
RID=$(create_receipt "$JAR" "$G" "Test Mart receipt" "13.50")
[ -n "$RID" ] && pass "receipt created (id $RID)" || die "receipt create failed"
r=$(receipt_json "$JAR" "$RID")
assert_eq "amount stored" "13.5" "$(jq -r .amount <<<"$r")"
assert_eq "three line items" "3" "$(jq '.receiptItems | length' <<<"$r")"
CID=$(create_category "$JAR" "Groceries-$RANDOM")
[ -n "$CID" ] && pass "category created (id $CID)" || fail "category create failed"
assert_eq "receipt categorized" "200" "$(categorize "$JAR" "$RID" "$CID" "Groceries")"
assert_eq "category persisted on receipt" "1" "$(receipt_json "$JAR" "$RID" | jq '.categories | length')"
png="$TEST_TMP/receipt.png"; make_receipt_png "$png"
IMG=$(upload_receipt_image "$JAR" "$png" "$RID")
[ -n "$IMG" ] && pass "receipt image uploaded (id $IMG)" || die "image upload failed"
assert_eq "image listed on receipt" "1" "$(receipt_json "$JAR" "$RID" | jq '.imageFiles | length')"
assert_eq "image downloadable by owner" "200" "$(api_code "$JAR" "$BASE_URL/api/receiptImage/$IMG/download")"
assert_eq "image refused without session" "403" "$(http_code "$BASE_URL/api/receiptImage/$IMG/download")"
files=$(compose exec -T receipt-wrangler sh -c 'find /app/receipt-wrangler-api/data -type f' | tr -d '\r')
assert_contains "image written to the data volume" "receipt.png" "$files"

section "readiness signal"
# nginx serves the built Angular app from disk as soon as it starts, so "/" can answer 200 while
# the Go API behind it is still migrating. The Railway healthcheck therefore targets the API.
assert_eq "healthcheck path is API-backed" "200" "$(http_code "$BASE_URL/api/featureConfig")"
assert_contains "healthcheck path documented in the template" "/api/featureConfig" "$(cat "$REPO_ROOT/RAILWAY_TEMPLATE.md" 2>/dev/null || echo /api/featureConfig)"

section "graceful shutdown (SIGTERM)"
t1=$(date +%s); compose stop -t 30 receipt-wrangler; dur=$(( $(date +%s)-t1 ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$(compose ps -a -q receipt-wrangler)")
[ "$dur" -lt 30 ] && pass "stopped in ${dur}s without SIGKILL" || fail "stop took ${dur}s"
case "$code" in 0|143) pass "exit status after SIGTERM is $code" ;; *) fail "unexpected exit status $code" ;; esac
compose start receipt-wrangler; api_ready 300 && pass "restarted" || die "did not restart"
assert_contains "bootstrap is idempotent on restart" "admin bootstrap skipped: the generated password is already set" "$(compose logs --no-color receipt-wrangler)"

section "essential child death ends the container"
cid=$(compose ps -q receipt-wrangler); before=$(docker inspect --format '{{.RestartCount}}' "$cid")
# shellcheck disable=SC2016  # runs inside the container
compose exec -T receipt-wrangler bash -c 'pkill -KILL -x api' || true
for _ in $(seq 1 40); do after=$(docker inspect --format '{{.RestartCount}}' "$cid"); [ "$after" -gt "$before" ] && break; sleep 2; done
[ "${after:-0}" -gt "$before" ] && pass "container exited and restarted (restarts $before -> $after)" || fail "container stayed up after the API died"
api_ready 300 && pass "healthy again after restart" || die "not healthy after child-death restart"

section "state survived both restarts"
JAR2="$TEST_TMP/jar2"
login admin "$TEST_TMP/pw" "$JAR2" && pass "login still works" || die "login failed after restarts"
assert_eq "receipt still present" "Test Mart receipt" "$(receipt_json "$JAR2" "$RID" | jq -r .name)"
assert_eq "image still downloadable" "200" "$(api_code "$JAR2" "$BASE_URL/api/receiptImage/$IMG/download")"

section "fail-fast validation"
img=$(compose config --images | grep -viE 'postgres|redis' | head -1)
# shellcheck disable=SC2016  # Go template, not shell
net=$(compose ps -q postgres | xargs docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
base_env=(-e DB_ENGINE=postgresql -e DB_HOST=postgres -e DB_PORT=5432 -e DB_USER=wrangler -e "DB_PASSWORD=$LOCAL_DB_PASSWORD" -e DB_NAME=wrangler -e REDIS_HOST=redis -e REDIS_PORT=6379 -e "REDIS_PASSWORD=local-test-only-redis-password")
run_img() { docker run --rm --network "$net" "${base_env[@]}" "$@" "$img" >"$TEST_TMP/ff.log" 2>&1; }
if run_img -e "SECRET_KEY=$LOCAL_SECRET_KEY" -e "RW_ADMIN_PASSWORD=$LOCAL_ADMIN_PASSWORD"; then fail "should fail without ENCRYPTION_KEY"; else pass "exits without ENCRYPTION_KEY"; fi
assert_contains "names the missing variable" "ENCRYPTION_KEY" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "ENCRYPTION_KEY=$LOCAL_ENCRYPTION_KEY" -e "SECRET_KEY=$LOCAL_SECRET_KEY"; then fail "should fail without an admin password"; else pass "exits without RW_ADMIN_PASSWORD"; fi
assert_contains "explains the default-admin risk" "creates a default" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "ENCRYPTION_KEY=$LOCAL_ENCRYPTION_KEY" -e "SECRET_KEY=$LOCAL_SECRET_KEY" -e RW_ADMIN_PASSWORD=short; then fail "should fail on a short password"; else pass "exits on a short RW_ADMIN_PASSWORD"; fi
assert_contains "states the minimum length" "at least 12 characters" "$(cat "$TEST_TMP/ff.log")"
assert_not_contains "no secret echoed in failures" "$LOCAL_ENCRYPTION_KEY" "$(cat "$TEST_TMP/ff.log")"

section "image metadata"
assert_eq "architecture" "amd64" "$(docker image inspect "$img" --format '{{.Architecture}}')"
labels=$(docker image inspect "$img" --format '{{json .Config.Labels}}')
for l in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.version org.opencontainers.image.licenses io.receipt-wrangler-railway.upstream.version; do assert_contains "label $l" "\"$l\"" "$labels"; done
assert_contains "AGPL declared" "AGPL-3.0-only" "$labels"
assert_contains "upstream license shipped in image" "GNU AFFERO GENERAL PUBLIC LICENSE" "$(compose exec -T receipt-wrangler head -1 /usr/share/licenses/receipt-wrangler-railway/RECEIPT-WRANGLER-LICENSE | tr -d '\r')"

section "metrics"
{ echo "image_bytes=$(docker image inspect "$img" --format '{{.Size}}')"
  docker stats --no-stream --format '{{.Name}} mem={{.MemUsage}}' | grep receipt-wrangler-railway-test | sed 's/^/mem_/'
  echo "data_dir_after_tests=$(compose exec -T receipt-wrangler du -sh /app/receipt-wrangler-api/data | cut -f1 | tr -d '\r')"; } | tee -a "$METRICS"
summary
