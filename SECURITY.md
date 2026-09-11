# Security policy

| Issue is in… | Report to |
|---|---|
| the wrapper: `Dockerfile`, `scripts/entrypoint.sh`, `scripts/bootstrap-admin.sh`, template variable wiring, exposure, secrets in logs, CI/publishing | this repository — GitHub "Report a vulnerability" on https://github.com/youssefsiam38/receipt-wrangler-railway/security, or an issue without exploit details |
| Receipt Wrangler itself (authentication, uploads, OCR/AI pipeline, API, dependencies) | upstream at https://github.com/Receipt-Wrangler/receipt-wrangler (no published security policy as of 2026-09-11) |

## What this wrapper does and does not protect

- **Replaces upstream's default `admin`/`admin` account password before the public listener
  starts.** This is the reason the wrapper exists. The smoke and public tests both assert that the
  default credentials are rejected.
- Fails to start if required variables are missing, rather than booting a half-configured instance.
- Never prints variable values; logs contain names, lengths and pass/fail only.
- Does **not** change upstream's nginx rate limits, session handling, or permissions model.
- Does **not** add SSO. Self-registration is off by default upstream (`EnableLocalSignUp=false`);
  add people from the admin UI.
- The generated administrator password lives in a Railway service variable until you change it in
  the app. Changing it there is expected and the wrapper will not revert it.

Only the newest published tag receives fixes; tags are never moved.
