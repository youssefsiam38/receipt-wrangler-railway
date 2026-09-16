# Upstream: Receipt Wrangler

Facts checked against primary sources on 2026-09-11. Re-verify before every upgrade.

## Identity

| Item | Value |
|---|---|
| Project | Receipt Wrangler — self-hosted receipt scanning, categorisation and sharing: upload or email receipts, extract fields with OCR or an AI provider, split them between group members, and track who owes what |
| Repository | https://github.com/Receipt-Wrangler/receipt-wrangler (monorepo: `api/`, `desktop/`, `mobile/`, `docker/`; the former separate repos are archived) |
| Documentation | https://receiptwrangler.io/docs (source: `Receipt-Wrangler/receipt-wrangler-doc`, AGPL-3.0) |
| Maintainer | the Receipt-Wrangler GitHub organisation (lead maintainer publishes images as `noah231515`) |
| License | **AGPL-3.0-only.** The repository root has no LICENSE file, but every distributed subproject does: `api/LICENSE`, `desktop/LICENSE` and `docker/LICENSE` are byte-identical copies of the GNU AGPL v3 text (sha256 prefix `8486a10c4393cee1`), and the archived `receipt-wrangler-monolith`, `receipt-wrangler-desktop`, `receipt-wrangler-core` and doc repositories are all labelled AGPL-3.0 by GitHub. |
| Activity (snapshot) | ~272 stars; last push 2026-09-11; releases roughly quarterly |
| Trademark / naming | "Receipt Wrangler" is the upstream project's name. This template is a *community-maintained Railway template for Receipt Wrangler*, *not affiliated with the Receipt Wrangler project*. |

### What AGPL-3.0 means for this template

The wrapper redistributes the upstream image unmodified plus two shell scripts, so the AGPL's
source-availability obligation applies to Receipt Wrangler itself. This repository therefore ships
the full licence text (`licenses/RECEIPT-WRANGLER-LICENSE`, also inside the image at
`/usr/share/licenses/receipt-wrangler-railway/`) and links to the exact upstream commit and tag in
`THIRD_PARTY_NOTICES.md`. Anyone who deploys this template and lets other people use it over a
network is a distributor under AGPL §13 and must be able to offer them the corresponding source;
the unmodified upstream tag linked here satisfies that. Modify the image and you take on that
obligation for your changes too.

## Pinned release

| Item | Value |
|---|---|
| Release | v7.1.0, published 2026-07-21 |
| Git commit | `6724f145e666…` (tag `v7.1.0`) |
| Image | `docker.io/noah231515/receipt-wrangler:v7.1.0` |
| Image index digest | `sha256:3a3a66266927adbecdca3815eba386b99bca519f02ebd700ae55a7690930bfa0` |
| Platforms | `linux/amd64` (`sha256:7ec5c39f183605653665eb5739b56011b59cccead9b4c4fdf8b729b61f3ca0f4`), `linux/arm64` (`sha256:1b68317c5e7cc0cafb364146cd95cc0124ca560367d5d05f280a701dfc214c55`) |
| Image source | Built from `docker/Dockerfile` in the monorepo: Angular desktop build on `node:lts-alpine`, then `golang:1.26-trixie` with the Go API, tesseract, ImageMagick, a Python venv, Chromium and nginx. |
| Image size | ~8.2 GB uncompressed (`linux/amd64`) — the single biggest operational consideration on Railway |
| Checksums | Upstream publishes no separate checksum files; the OCI digests above are the integrity anchor, read with `docker buildx imagetools inspect`. |

## Wrapper image releases

| Wrapper tag | Index digest | Notes |
|---|---|---|
| `ghcr.io/youssefsiam38/receipt-wrangler-railway:1.0.5` | `sha256:8aa4dfed66d2566aaa05b1ab06bc135ae5c030b66b8e3c5aa0a3a5edba649153` | superseded; amd64 `sha256:e684a94ec60418ef0c50f9532385fd9b6217cafd78e6943a1a8c7eb7ea14fd1f`, arm64 `sha256:428edadd238e518d5ae18ac186def2f56a6fe80f982400a4f91600f03f28bf91` |
| `ghcr.io/youssefsiam38/receipt-wrangler-railway:1.0.6` | `sha256:5a0afb38e296b5f3f9412df4cdc5e506ad336e7c51c3cec5fa885b280b07a636` | current; logs routine start-up lines on stdout, tag commit `45477393351e56d0d4c2d3f0f01a99ba86b61a47` |
| 1.0.0, 1.0.2 | not published | publish workflow failed on flaky test reads before any image was pushed; tags kept, never reused |
| 1.0.1, 1.0.3, 1.0.4 | published, superseded | see releases |

## Runtime facts (verified by running the pinned image)

| Item | Value |
|---|---|
| Container entrypoint | `/app/entrypoint.sh` (bash) as root: sources the Python venv, then runs `./api --env prod &` and `nginx -g 'daemon off;' &`, `wait -n`, and exits when either child exits. Traps TERM/INT and forwards them. |
| Listeners | nginx on `0.0.0.0:80` (public); the Go API on `0.0.0.0:8081` behind it |
| nginx | serves the Angular app, proxies `/api/`, `/oauth/`, `/mcp` and the OAuth well-known routes to `localhost:8081`, `client_max_body_size 50M`, and rate-limits login (30/min), signup (2/min), search and general API |
| Database | PostgreSQL, MariaDB/MySQL or SQLite via `DB_ENGINE`. PostgreSQL DSN is built with `sslmode=disable` (`internal/repositories/db.go`), so the database must accept non-TLS connections — true over Railway's private network. |
| Redis | required; used by asynq for background jobs (OCR, email polling, system tasks) |
| Migrations | run automatically at start (`MakeMigrations` then `InitDB` in `main.go`); startup aborts on failure |
| **First run** | `InitDB` → `CreateUserIfNoneExist` creates a **default administrator `admin` / `admin`** (`internal/commands/constants.go`) when the user table is empty. The app flags the first admin login so the UI can prompt for a change, but the account is live the moment the service is reachable. |
| Local signup | `SystemSettings.EnableLocalSignUp` defaults to **false**, so strangers cannot self-register; the default admin account is the real first-run risk. |
| Passwords | bcrypt cost 14 (`internal/utils/auth.go`) |
| Auth | `POST /api/login` with JSON `{username,password}` sets HttpOnly JWT + refresh cookies; API keys and an OAuth-protected MCP server are optional |
| Persistent paths | `/app/receipt-wrangler-api/data` (receipt images, `<groupId>-<groupName>/<receiptId>-<n>-<file>`), `/app/receipt-wrangler-api/logs`, `/app/receipt-wrangler-api/sqlite` (only with `DB_ENGINE=sqlite`) |
| Health | no dedicated health route. `GET /` (the Angular app through nginx) returns 200 only once nginx is up, and `GET /api/featureConfig` returns 200 from the API without authentication. |
| Idle memory | ~60 MiB for the app container after boot (local measurement) |
| Startup | ~29 s to a serving web UI on a warm image, including the wrapper's admin bootstrap |

## Environment variables (upstream, `internal/constants/env_variables.go`)

Required: `ENCRYPTION_KEY`, `SECRET_KEY`. Database: `DB_ENGINE`, `DB_HOST`, `DB_PORT`, `DB_USER`,
`DB_PASSWORD`, `DB_NAME`, `DB_FILENAME` (sqlite). Redis: `REDIS_HOST`, `REDIS_PORT`, `REDIS_USER`,
`REDIS_PASSWORD`. Other: `BASE_PATH`, `ENV`, `CHROMIUM_BINARY_PATH`, `CHROMIUM_SANDBOX`,
`CHROMIUM_ALLOW_EXTERNAL_RESOURCES`. Everything else (OCR/AI providers, SMTP, email polling,
currency, MCP) is configured in the app's System Settings and stored in the database.

## Backup and restore

- Database: `pg_dump` from the PostgreSQL service.
- Receipt images: copy `/app/receipt-wrangler-api/data` (Railway: `railway volume files download`).
- Take both together: image paths are referenced from the database.

## Upgrade and migration

Schema migrations run at startup; back up first. Upstream release notes:
https://github.com/Receipt-Wrangler/receipt-wrangler/releases.

## Known Railway constraints

- One volume per service; single replica; brief downtime on redeploy.
- The ~8.2 GB image makes the first deploy slow and consumes build/runtime disk.
- Railway healthchecks run only at deploy time.
- Railway's template generator rejects `@sha256` image references; the template uses the `v7.1.0`
  tag and this file records the digest.
