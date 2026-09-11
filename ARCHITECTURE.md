# Architecture

## Selected topology: three Railway services

```
              HTTPS (Railway edge)
                      │
                      ▼
┌──────────────────────────────────────────┐      ┌──────────────────────────┐
│ service: receipt-wrangler                │ IPv6 │ service: Postgres        │
│ image: ghcr.io/youssefsiam38/receipt-    │ priv │ Railway PostgreSQL       │
│        wrangler-railway:<version>        │ ───▶ │ own volume               │
│   (wraps noah231515/receipt-wrangler     │      └──────────────────────────┘
│    :v7.1.0)                              │      ┌──────────────────────────┐
│ wrapper entrypoint → upstream entrypoint │ ───▶ │ service: Redis           │
│   ├─ ./api --env prod        :8081       │      │ Railway Redis (asynq)    │
│   └─ nginx                   :80 public  │      └──────────────────────────┘
│ volume: /app/receipt-wrangler-api/data   │
│ public domain → port 80, healthcheck /   │
└──────────────────────────────────────────┘
```

| Service | Source | Public | Volume | Why |
|---|---|---|---|---|
| `receipt-wrangler` | this repository's wrapper image (GHCR, version tag, digest recorded per release) | yes, port 80 | `/app/receipt-wrangler-api/data` (receipt images) | upstream ships one container that runs the Go API and nginx together; splitting them would fork their nginx config for no benefit |
| `Postgres` | Railway PostgreSQL | no | managed | upstream supports PostgreSQL, MariaDB/MySQL or SQLite; PostgreSQL is the documented production choice and Railway manages backups and upgrades for its own database services |
| `Redis` | Railway Redis | no | managed | required: asynq runs OCR, email polling and system tasks through Redis |

SQLite would remove a service but puts the database on the same single volume as the images and
gives up Railway's managed backups; PostgreSQL is worth the extra service here.

Inter-service traffic uses Railway private networking with reference variables, so no connection
string is duplicated:

```
DB_HOST     = ${{Postgres.RAILWAY_PRIVATE_DOMAIN}}   DB_USER/DB_PASSWORD/DB_NAME = ${{Postgres.PG*}}
REDIS_HOST  = ${{Redis.RAILWAY_PRIVATE_DOMAIN}}      REDIS_PASSWORD = ${{Redis.REDIS_PASSWORD}}
```

Receipt Wrangler builds its PostgreSQL DSN with `sslmode=disable`, which is correct over Railway's
private network and is why the database must not be exposed publicly.

## Why a wrapper image

On an empty database Receipt Wrangler creates a **default administrator `admin` / `admin`**
(`CreateUserIfNoneExist` → `GetDefaultAdminSignUpCommand`). Railway assigns the public domain at
deploy time, so without intervention every new deployment is briefly, and then indefinitely,
reachable with well-known credentials. Self-registration is not the risk: `EnableLocalSignUp`
defaults to false.

The wrapper closes that window without touching application code:

1. Validates required variables (`ENCRYPTION_KEY`, `SECRET_KEY`, database and Redis settings,
   admin password length). Values are never logged.
2. Starts **only the Go API** (`./api --env prod`) on `127.0.0.1:8081`. nginx — the process that
   listens on the port Railway routes to — stays down, so nothing is publicly reachable yet.
3. Runs `bootstrap-admin.sh`, which uses the app's own REST API: log in as `admin`/`admin`, call
   `POST /api/user/{id}/resetPassword` with the generated password, then prove the new password
   works and the default one does not.
4. Stops that API and `exec`s the upstream entrypoint, which starts the API and nginx together.

The bootstrap is idempotent and conservative:

| State on start | Action |
|---|---|
| generated password already works | skip |
| `admin`/`admin` works | reset to the generated password, verify both directions |
| neither works (owner changed it in the app) | leave it alone, log that `RW_ADMIN_PASSWORD` is stale, and verify the default credentials are still unusable before continuing |

That last row matters: changing your password in the app is the behaviour we want, and it must not
make the container refuse to boot or silently revert your choice. The only condition that aborts
startup is the default account still being usable after a reset attempt.

## Health check

Railway healthcheck path: `/api/featureConfig`, timeout 600 s (the image is ~8.2 GB, so the first
pull is slow).

Upstream has no dedicated health route. `/` is **not** a usable readiness signal: nginx serves the
built Angular app straight from disk, so it answers 200 while the Go API behind it is still running
migrations — a local test caught exactly that, logging in successfully against a served page only
after the API had finished. `/api/featureConfig` is proxied to the API, needs no authentication,
returns a tiny JSON body, and therefore answers 200 only once the API is accepting requests, which
is after migrations have completed. It leaks nothing beyond two booleans that the login page
already reads.

## Persistence and replicas

One volume for receipt images, one replica, brief downtime on redeploy. The database and Redis are
Railway-managed services with their own storage. Back up the database and the image volume
together: image paths are referenced from the database.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Upstream image directly | default `admin`/`admin` reachable on the public URL |
| Writing the bcrypt hash straight into the database | duplicates upstream's password schema and cost factor; the REST API is upstream's own code path and stays correct across releases |
| Deleting the default user and creating a fresh admin | loses the bootstrap user's group memberships ("My Receipts", "All") that the app creates alongside it |
| SQLite single service | database and images share one volume; no managed backups |
| Self-hosted Postgres/Redis images instead of Railway's | Railway's own database services give people backups, metrics and upgrades they expect |
