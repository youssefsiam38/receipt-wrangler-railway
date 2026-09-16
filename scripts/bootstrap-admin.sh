#!/bin/bash
# Replaces Receipt Wrangler's built-in admin/admin bootstrap password with a generated one, using
# the application's own REST API, before nginx (the public listener) is ever started. Runs against
# 127.0.0.1:8081 while only the API process is up. Never prints values.
#
# Outcomes:
#   - the generated password already works        -> nothing to do
#   - upstream's default admin/admin works        -> reset it to the generated password
#   - neither works (owner changed it in the app) -> leave it alone and continue, after proving
#                                                    that the default credentials are not usable
set -u

# Railway colours a log line by the stream it arrived on, so routine start-up messages go to stdout
# and only failures go to stderr; otherwise the whole first boot is shown to the deployer in red.
log()  { printf '[receipt-wrangler-railway] %s\n' "$*"; }
fail() { printf '[receipt-wrangler-railway] FATAL: %s\n' "$*" >&2; exit 1; }

API=http://127.0.0.1:8081
USERNAME=${RW_ADMIN_USERNAME:-admin}
PASSWORD=${RW_ADMIN_PASSWORD:-}
[ -n "$PASSWORD" ] || fail "RW_ADMIN_PASSWORD is empty"

jar=$(mktemp); body=$(mktemp); trap 'rm -f "$jar" "$body"' EXIT

# try_login USER PASSWORD [COOKIE_JAR] -> echoes the HTTP status
try_login() {
  local u=$1 p=$2 jarfile=${3:-}
  local args=(-s -o "$body" -w '%{http_code}' -X POST "$API/api/login" -H 'Content-Type: application/json'
              --data "$(jq -nc --arg u "$u" --arg p "$p" '{username:$u,password:$p}')")
  [ -n "$jarfile" ] && args+=(-c "$jarfile")
  curl "${args[@]}" || echo 000
}

if [ "$(try_login "$USERNAME" "$PASSWORD")" = "200" ]; then
  log "admin bootstrap skipped: the generated password is already set"
  exit 0
fi

if [ "$(try_login "$USERNAME" admin "$jar")" != "200" ]; then
  # Neither password works. The safe reading is that the administrator password was changed inside
  # the app, which is exactly what we want people to do; do not touch it and do not block startup.
  log "admin bootstrap skipped: \"$USERNAME\" uses neither the generated password nor upstream's default, so it was changed in the app. RW_ADMIN_PASSWORD is now stale and is ignored."
  if [ "$(try_login admin admin)" = "200" ]; then
    fail "upstream's default admin/admin account is still usable; refusing to expose this deployment"
  fi
  log "verified that the default admin/admin credentials are not usable"
  exit 0
fi

log "signed in with upstream's default bootstrap credentials"
uid=$(jq -r '.claims.userId // .id // .userId // empty' "$body" 2>/dev/null)
if [ -z "$uid" ]; then
  uid=$(curl -s -b "$jar" "$API/api/user" | jq -r --arg u "$USERNAME" '[.[] | select(.username==$u)][0].id // empty' 2>/dev/null)
fi
[ -n "$uid" ] || fail "could not determine the administrator's user id"

code=$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" -X POST "$API/api/user/$uid/resetPassword" \
  -H 'Content-Type: application/json' --data "$(jq -nc --arg p "$PASSWORD" '{password:$p}')" || echo 000)
[ "$code" = "200" ] || fail "password reset returned HTTP $code"

[ "$(try_login "$USERNAME" "$PASSWORD")" = "200" ] || fail "the generated password does not work after the reset"
[ "$(try_login "$USERNAME" admin)" != "200" ] || fail "upstream's default password still works after the reset"
[ "$(try_login admin admin)" != "200" ] || fail "the default admin/admin account is still usable after the reset"

log "admin bootstrap complete: \"$USERNAME\" now uses the generated password (length ${#PASSWORD})"
