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
BOOTSTRAP=/usr/local/bin/receipt-wrangler-railway-bootstrap
[ -x "$API_DIR/api" ] || fail "the Receipt Wrangler API binary is missing from the image"
command -v nginx >/dev/null || fail "nginx is missing from the image"

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
  # shellcheck disable=SC2317  # invoked via trap
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

# --- run the API and nginx ------------------------------------------------------------------------
# Upstream's entrypoint starts both and exits when either does, but it sends nginx's errors to
# /var/log/nginx/error.log inside the container, where a hosting platform never sees them. We start
# the same two processes here with nginx logging to stderr, so a failure to bind or start is visible
# in the platform's logs, and keep the same "exit when either child exits" behaviour.
# One line of evidence about what nginx will actually serve; platforms only show stdout/stderr,
# and a wrong server block is otherwise invisible until someone hits the wrong page.
log "nginx config: $(nginx -T 2>/dev/null | grep -cE '^\s*server \{') server block(s), listeners:$(nginx -T 2>/dev/null | grep -oE '^\s*listen [^;]+' | sed 's/^ *listen /  /' | tr '\n' ' ')"
log "starting Receipt Wrangler: API on 8081, nginx on ${PORT:-80}"
./api --env prod &
api_pid=$!
nginx -g "daemon off; error_log /dev/stderr info;" &
nginx_pid=$!

# shellcheck disable=SC2317  # invoked via trap
forward() {
  log "stop signal received, stopping nginx and the API"
  kill -TERM "$nginx_pid" "$api_pid" 2>/dev/null
  wait "$nginx_pid" "$api_pid" 2>/dev/null
  exit 143
}
trap forward TERM INT

wait -n
code=$?
log "a child process exited with status $code; stopping the container so the platform can restart it"
kill -TERM "$nginx_pid" "$api_pid" 2>/dev/null
wait 2>/dev/null || true
exit "$code"
