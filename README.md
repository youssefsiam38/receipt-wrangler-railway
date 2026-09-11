# Receipt Wrangler on Railway

Photograph a receipt, get structured data you can share. **Receipt Wrangler** extracts the
merchant, date, total and line items with OCR (or an AI provider you choose), lets you categorise
and tag receipts, split them across a group, and see who owes whom. Web app, iOS/Android apps,
per-group permissions, custom fields, email ingestion and exports. This repository is a
**community-maintained Railway template** for
[Receipt Wrangler](https://github.com/Receipt-Wrangler/receipt-wrangler). It is **not affiliated
with the Receipt Wrangler project**.

<!-- DEPLOY_BUTTON_START -->
_Deploy button will appear here after the template is published._
<!-- DEPLOY_BUTTON_END -->

> **Licence.** Receipt Wrangler is **AGPL-3.0**. This template deploys the upstream release
> unmodified. If you let other people use your deployment over a network you are a distributor
> under AGPL §13 and must be able to offer them the corresponding source; see
> [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), which links the exact upstream tag. The wrapper
> code in this repository is MIT.

## What you get

| Service | Source | Public | Volume |
|---|---|---|---|
| `receipt-wrangler` | `ghcr.io/youssefsiam38/receipt-wrangler-railway:<version>` wrapping `noah231515/receipt-wrangler:v7.1.0` | yes, port 80 | `/app/receipt-wrangler-api/data` — receipt images |
| `Postgres` | Railway PostgreSQL | no | managed |
| `Redis` | Railway Redis | no | managed |

| Component | Version |
|---|---|
| Receipt Wrangler | v7.1.0 |
| Wrapper | see [releases](https://github.com/youssefsiam38/receipt-wrangler-railway/releases) |

Why a wrapper and why these three services: [ARCHITECTURE.md](ARCHITECTURE.md). In one sentence:
Receipt Wrangler creates a default `admin`/`admin` account on first start, and the wrapper replaces
that password with a generated one **before** the public listener starts.

## First run

1. Click **Deploy on Railway**. Nothing has to be filled in: the encryption key, secret key and
   administrator password are generated. The image is ~8.2 GB, so the first deploy is slow.
2. Open the `receipt-wrangler` service's public URL. Sign in as `admin` with the value of the
   service variable `RW_ADMIN_PASSWORD` (Railway dashboard → `receipt-wrangler` → Variables →
   click to reveal).
3. **Change the password in the app** (avatar → account). The wrapper notices and leaves your
   password alone from then on; `RW_ADMIN_PASSWORD` becomes a stale, ignored variable.
4. Add the people you share expenses with (users screen) and create a group for them.
   Self-registration is off by default upstream; you add accounts.
5. Upload a receipt. Extraction runs as a background job through Redis; open the receipt to correct
   fields, add line items and assign who is charged.
6. Optional: System Settings has OCR/AI provider settings (OpenAI, Gemini, Ollama), IMAP email
   ingestion, SMTP, currency formatting and the MCP server.

## Environment variables (`receipt-wrangler` service)

| Variable | Required | Set by template | Description |
|---|---|---|---|
| `ENCRYPTION_KEY` | yes | generated `${{secret(64, "abcdef0123456789")}}` | Encrypts stored third-party credentials (SMTP, AI providers, API keys). Changing it makes existing stored credentials unreadable. |
| `SECRET_KEY` | yes | generated `${{secret(64, "abcdef0123456789")}}` | Signs JWT session tokens. Changing it signs everyone out. |
| `RW_ADMIN_PASSWORD` | yes | generated `${{secret(24)}}` | Wrapper: replaces upstream's default `admin` password on first start. Ignored once you change the password in the app. |
| `RW_ADMIN_USERNAME` | no | `admin` | Wrapper: the account whose password is replaced. Upstream always creates `admin`. |
| `DB_ENGINE` | yes | `postgresql` | Also supports `mariadb`, `mysql`, `sqlite`. |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | yes | references to the `Postgres` service | Connection details over Railway private networking (the app connects with `sslmode=disable`, which is why the database stays private). |
| `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` | yes | references to the `Redis` service | Background job queue. |
| `RW_ALLOW_DEFAULT_ADMIN` | no | unset | Set `true` only if you deliberately want upstream's default `admin`/`admin` behaviour. Not recommended on a public URL. |
| `APP_READY_TIMEOUT` | no | `300` | Wrapper: seconds to wait for the API during the pre-start phase. |
| `BASE_PATH`, `CHROMIUM_*` | no | unset | Upstream advanced settings; see `api/internal/constants/env_variables.go`. |

OCR/AI providers, SMTP, IMAP and currency formatting are configured in the app's System Settings
and stored in the database, not as variables.

## Persistent paths

| Path | Contents | Backup |
|---|---|---|
| `/app/receipt-wrangler-api/data` | receipt images, `<groupId>-<groupName>/<receiptId>-<n>-<file>` | `railway volume files download` |
| PostgreSQL | receipts, users, groups, settings, jobs | `pg_dump` |

Back both up together: image paths are referenced from the database.

## Public routes

| Route | Auth | Purpose |
|---|---|---|
| `/` | no | web app (static files served by nginx) |
| `/api/featureConfig` | no | **Railway healthcheck**: proxied to the API, so 200 means the API is up, not just nginx |
| `/api/login` | no | sign in; nginx rate-limits this to 30 requests per minute |
| `/api/*` | session or API key | application API |
| `/oauth/*`, `/mcp`, `/.well-known/oauth-*` | varies | optional MCP server (disabled by default) |

Only the app service is public. PostgreSQL and Redis are reachable only on the private network.

## Run locally

Requires Docker with Compose v2, `curl`, `jq`, `python3`, and about 20 GB of free disk.

```bash
docker compose build
docker compose up -d
# http://localhost:9082  (admin / local-test-only-admin-password)
```

Tests:

```bash
tests/static.sh        # shellcheck, python syntax, compose config, pinned tag+digest, SHA-pinned actions
tests/smoke.sh         # cold start, default creds rejected, receipt + items + category + image, SIGTERM, child death, fail-fast
tests/persistence.sh   # receipt, image bytes and password survive recreation; an in-app password change is never reverted
tests/railway-smoke.sh https://your-app.up.railway.app   # public checks against a deployment
```

## Backup and restore

```bash
railway volume files download --service receipt-wrangler /app/receipt-wrangler-api/data ./rw-images
```

Dump the database from the Railway Postgres service, and restore both together onto a fresh
deployment before first use.

## Upgrades

Each wrapper release pins one Receipt Wrangler version (tag and digest). Migrations run at startup;
back up first. Maintainer process: [MAINTENANCE.md](MAINTENANCE.md).

## Resource use and cost

Railway bills CPU, memory, volume storage and egress ([pricing](https://railway.com/pricing)).

| Metric | Value |
|---|---|
| Image | ~8.2 GB uncompressed — the first deploy is dominated by the pull |
| App idle memory | ~60 MiB after boot (local measurement) |
| Cold start to a ready API | ~15–30 s on a warm image, including the admin bootstrap |
| Storage | receipt images plus the database; both grow with use |

Cost drivers: three always-on services, the large image, OCR CPU time when receipts are processed,
and volume size. Using a cloud AI provider moves extraction cost off Railway and onto that provider.

## Security

- The default `admin`/`admin` account's password is replaced before the service is exposed; the
  smoke and public tests both assert the default credentials are rejected.
- Self-registration is disabled by default upstream; you add users from the admin UI.
- `ENCRYPTION_KEY` and `SECRET_KEY` are generated per deployment and never logged by the wrapper.
- nginx rate-limits login, signup and search upstream.
- Report wrapper issues via [SECURITY.md](SECURITY.md).

## Known limitations

- Single replica for the app service (volume); brief downtime on redeploy.
- The ~8.2 GB image makes deploys and redeploys slow.
- OCR is CPU-bound; large PDFs use Chromium and ImageMagick inside the container.
- Railway healthchecks run at deploy time only.
- On a small instance the API can return 502 for a few seconds right after an upload, while the
  OCR job it queued competes for CPU. Give the service more CPU, or use a cloud AI provider, if
  you upload many receipts at once.
- `linux/arm64` is published upstream but only `amd64` is tested here.
- The generated administrator password stays in a Railway variable until you change it in the app.

## Legal and data

Receipts contain personal and financial information about you and the people you share with. You
are the data controller for your deployment: choose an appropriate region, keep backups, and tell
your group what you store. If you enable a cloud AI provider, receipt images and text are sent to
that provider.

## Links

- Upstream: https://github.com/Receipt-Wrangler/receipt-wrangler (AGPL-3.0) · docs https://receiptwrangler.io
- Wrapper image: https://github.com/youssefsiam38/receipt-wrangler-railway/pkgs/container/receipt-wrangler-railway
- [LICENSE](LICENSE) (wrapper, MIT) · [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [UPSTREAM.md](UPSTREAM.md) · [MARKETPLACE_AUDIT.md](MARKETPLACE_AUDIT.md)
