#!/bin/bash
# receipt-wrangler-railway entrypoint.
#
#   1. validate variables (names only; values are never printed)
#   2. start ONLY the API on loopback-reachable 127.0.0.1:8081 (nginx, the public listener on
#      port 80, stays down) and replace upstream's admin/admin bootstrap password with the
#      generated one, so the default credentials are never reachable from the internet
#   3. stop that API and exec the upstream entrypoint, which runs the API and nginx together
set -u

log()  { printf '[receipt-wrangler-railway] %s\n' "$*" >&2; }
fail() { log "FATAL: $*"; exit 1; }

: "${APP_READY_TIMEOUT:=300}"
API_DIR=/app/receipt-wrangler-api
UPSTREAM_ENTRYPOINT=/app/entrypoint.sh
BOOTSTRAP=/usr/local/bin/receipt-wrangler-railway-bootstrap
[ -x "$UPSTREAM_ENTRYPOINT" ] || fail "upstream entrypoint $UPSTREAM_ENTRYPOINT not found in image"

# --- required variables -------------------------------------------------------------------------
missing=""
for v in ENCRYPTION_KEY SECRET_KEY DB_ENGINE DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME REDIS_HOST REDIS_PORT; do
  eval "val=\${$v:-}"
  [ -n "$val" ] || missing="$missing $v"
done
[ -z "$missing" ] || fail "missing required variable(s):$missing"
[ "${#ENCRYPTION_KEY}" -ge 16 ] || fail "ENCRYPTION_KEY must be at least 16 characters"
[ "${#SECRET_KEY}" -ge 16 ] || fail "SECRET_KEY must be at least 16 characters"
case "$DB_ENGINE" in postgresql|mariadb|mysql|sqlite) ;; *) fail "DB_ENGINE must be postgresql, mariadb, mysql or sqlite" ;; esac

if [ -n "${RW_ADMIN_PASSWORD:-}" ]; then
  [ "${#RW_ADMIN_PASSWORD}" -ge 12 ] || fail "RW_ADMIN_PASSWORD must be at least 12 characters"
  bootstrap_mode=1
elif [ "${RW_ALLOW_DEFAULT_ADMIN:-false}" = "true" ]; then
  bootstrap_mode=0
  log "WARNING: RW_ALLOW_DEFAULT_ADMIN=true - starting with upstream's default admin/admin credentials reachable on the public URL"
else
  fail "no administrator password configured. Receipt Wrangler creates a default \"admin\"/\"admin\" account on first start, so set RW_ADMIN_PASSWORD (and optionally RW_ADMIN_USERNAME) to have it replaced before the service is exposed, or set RW_ALLOW_DEFAULT_ADMIN=true to accept the default credentials (not recommended on a public URL)."
fi

cd "$API_DIR" || fail "$API_DIR missing"
# shellcheck disable=SC1091
[ -f "$API_DIR/wranglervenv/bin/activate" ] && . "$API_DIR/wranglervenv/bin/activate"

if [ "$bootstrap_mode" = 1 ]; then
  log "pre-start: launching the API alone (nginx stays down) to set the administrator password"
  ./api --env prod &
  api_pid=$!
  on_signal() { log "stop signal received during bootstrap"; kill -TERM "$api_pid" 2>/dev/null; wait "$api_pid"; exit 143; }
  trap on_signal TERM INT

  deadline=$(( $(date +%s) + APP_READY_TIMEOUT ))
  until curl -fsS -m 5 -o /dev/null "http://127.0.0.1:8081/api/featureConfig" 2>/dev/null; do
    if ! kill -0 "$api_pid" 2>/dev/null; then wait "$api_pid"; fail "the API exited during the pre-start phase with status $?"; fi
    [ "$(date +%s)" -lt "$deadline" ] || { kill -TERM "$api_pid" 2>/dev/null; wait "$api_pid"; fail "the API did not become reachable within ${APP_READY_TIMEOUT}s"; }
    sleep 2
  done
  log "API is reachable on loopback; setting the administrator password"
  if ! "$BOOTSTRAP"; then kill -TERM "$api_pid" 2>/dev/null; wait "$api_pid"; fail "administrator bootstrap failed"; fi

  log "stopping the pre-start API"
  kill -TERM "$api_pid" 2>/dev/null
  wait "$api_pid" 2>/dev/null || true
  trap - TERM INT
fi

log "starting Receipt Wrangler (API + nginx) on port 80"
exec "$UPSTREAM_ENTRYPOINT" "$@"
