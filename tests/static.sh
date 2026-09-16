#!/usr/bin/env bash
# Static validation: shell syntax, shellcheck, compose config, Dockerfile pins.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. tests/lib.sh

section "shell syntax"
for f in scripts/*.sh tests/*.sh; do
  if sh -n "$f" 2>/dev/null || bash -n "$f"; then pass "syntax $f"; else fail "syntax $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -s bash scripts/*.sh; then pass "shellcheck scripts"; else fail "shellcheck scripts"; fi
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if compose config -q; then pass "compose config"; else fail "compose config"; fi

section "dockerfile pins"
base=$(grep -E '^ARG RECEIPT_WRANGLER_IMAGE=' Dockerfile | cut -d= -f2)
if printf '%s' "$base" | grep -qE ':v[0-9.]+@sha256:[0-9a-f]{64}$'; then pass "base image pinned by tag and digest"; else fail "base image not pinned: $base"; fi
if grep -qE '^ENTRYPOINT \["/usr/local/bin/receipt-wrangler-railway-entrypoint"' Dockerfile; then pass "entrypoint is the wrapper"; else fail "wrapper entrypoint missing"; fi
if python3 -m py_compile tests/fixtures/make-receipt.py; then pass "make-receipt.py compiles"; else fail "make-receipt.py"; fi
for f in .github/workflows/*.yml; do
  if grep -E 'uses: ' "$f" | grep -vqE '@[0-9a-f]{40}( |$)'; then fail "unpinned action in $f"; else pass "actions pinned by SHA in $f"; fi
done

section "log streams"
# Railway colours a log line by the stream it arrived on: routine lines on stderr show as errors.
for ep in scripts/entrypoint.sh scripts/bootstrap-admin.sh; do
  if grep -q '^log()' "$ep" && ! grep '^log()' "$ep" | grep -q '>&2'; then
    pass "routine logs go to stdout: $ep"
  else
    fail "log() writes to stderr; Railway would show every start-up line as an error: $ep"
  fi
  if grep '^fail()' "$ep" | grep -q '>&2'; then pass "failures go to stderr: $ep"; else fail "fail() does not write to stderr: $ep"; fi
done

section "no tracked secrets"
if git -C "$REPO_ROOT" rev-parse >/dev/null 2>&1; then
  hits=$(git -C "$REPO_ROOT" ls-files -z | xargs -0 grep -lE '(ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]+)' 2>/dev/null || true)
  if [ -z "$hits" ]; then pass "no credential patterns in tracked files"; else fail "credential pattern in: $hits"; fi
  if git -C "$REPO_ROOT" ls-files | grep -qE '(^|/)\.env$'; then fail ".env is tracked"; else pass ".env not tracked"; fi
else
  echo "  SKIP  not a git checkout"
fi
summary
