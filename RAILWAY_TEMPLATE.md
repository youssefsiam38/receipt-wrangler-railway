# Deploy and Host Receipt Wrangler

Receipt Wrangler turns a photo of a receipt into structured data you can share. Upload or email a
receipt, let OCR (or an AI provider you configure) pull out the merchant, date, total and line
items, categorise and tag it, split it across a group, and track who owes whom. It has a web app,
iOS/Android apps, per-group permissions, custom fields, exports and an optional MCP server. This is
a community-maintained template and is not affiliated with the Receipt Wrangler project.

Receipt Wrangler is licensed under the **AGPL-3.0**. If you let other people use your deployment
over a network, you are responsible for offering them the corresponding source; the template
deploys the upstream release unmodified and links to it.

## About Hosting

Three Railway services:

- **receipt-wrangler** — the upstream monolith (Go API + Angular web app behind nginx) from a
  version-pinned wrapper image, `ghcr.io/youssefsiam38/receipt-wrangler-railway`. It takes the
  public HTTPS domain on port 80 and a volume for receipt images.
- **Postgres** — Railway PostgreSQL, private network only.
- **Redis** — Railway Redis, private network only; the background job queue (OCR, email polling,
  scheduled tasks) needs it.

Receipt Wrangler creates a default `admin` / `admin` administrator the first time it starts. The
wrapper replaces that password with a per-deployment generated one **before** nginx, the public
listener, is ever started, so the default credentials are never reachable from the internet. Sign
in the first time with the generated password from the service variables, then change it in the
app; the wrapper will not revert your choice. Self-registration is off by default upstream.

The healthcheck targets `/api/featureConfig`, which is proxied to the API, so a deployment only goes
live once the API is answering and migrations are done. Schema migrations run automatically at
start. The service runs a single replica with a volume, so redeploys have a few seconds of downtime.

## Why Deploy

- Receipts, line items and balances stay on infrastructure you control instead of a receipt-scanning
  SaaS that mines purchase data.
- No default credentials to forget about: the administrator password is generated per deployment.
- Bring your own extraction: built-in OCR (Tesseract) works offline, or point it at OpenAI, Gemini
  or a local Ollama instance from the settings screen.
- Pinned versions (never `latest`), with digests recorded in the repository.

## Common Use Cases

- Households and roommates splitting groceries and utilities with the receipt attached as evidence.
- Freelancers and small teams collecting expense receipts for reimbursement and export at tax time.
- Anyone who wants searchable, categorised receipts with the original image kept alongside.

## Dependencies for Receipt Wrangler

- Nothing external is required to start: OCR runs in the container.
- Optional: an AI provider key (OpenAI, Gemini, Ollama) for better extraction; an IMAP mailbox for
  emailing receipts in; SMTP for notifications. All are configured in the app, not as variables.

### Deployment Dependencies

- A Railway plan with volumes and three services. The image is about 8.2 GB, so the first deploy is
  slow and uses meaningful disk.
- No values are required at deploy time: the encryption key, secret key and administrator password
  are generated.
- Source and documentation: https://github.com/youssefsiam38/receipt-wrangler-railway
- Upstream project: https://github.com/Receipt-Wrangler/receipt-wrangler (AGPL-3.0) ·
  https://receiptwrangler.io

## After Deploying

1. Wait for all three services to be healthy. The first deploy pulls a large image; allow time.
2. Open the `receipt-wrangler` service's public URL and sign in as `admin` with the password in the
   service variable `RW_ADMIN_PASSWORD` (Railway dashboard → `receipt-wrangler` → Variables).
3. Change the password in the app (avatar → account). The wrapper detects this and leaves it alone.
4. Add the people you share expenses with from the users screen, and create a group for them.
5. Upload a receipt: the OCR job runs in the background through Redis; open the receipt to correct
   the extracted fields, add line items and assign who is charged for what.
6. Optional: set an AI provider or IMAP mailbox in System Settings; install the mobile apps.

Resource expectations: roughly 60 MiB of memory for the app container at idle, more while OCR runs;
the database and Redis are small; receipt images grow the volume. Limitations: single replica;
about 8.2 GB image; OCR is CPU-bound; the generated administrator password sits in a Railway
variable until you change it in the app.
