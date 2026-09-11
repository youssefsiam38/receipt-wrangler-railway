# Maintenance

## Watch upstream

- Releases: https://github.com/Receipt-Wrangler/receipt-wrangler/releases
  (`gh release list -R Receipt-Wrangler/receipt-wrangler`)
- Images: `curl -s "https://hub.docker.com/v2/repositories/noah231515/receipt-wrangler/tags?page_size=20" | jq -r '.results[].name'`
  (use the `vX.Y.Z` multi-arch tag, not `latest` or the `-amd64`/`-arm64` single-arch ones)
- Upstream has no security advisory feed; review releases monthly and within 48 h of any release
  that mentions auth, uploads, or dependency bumps.

## Verify new inputs

```bash
docker buildx imagetools inspect noah231515/receipt-wrangler:vX.Y.Z     # index + per-arch digests
gh api repos/Receipt-Wrangler/receipt-wrangler/git/ref/tags/vX.Y.Z --jq .object.sha
```

Re-check the licence position each time: the repository root still has no LICENSE file, so confirm
`api/LICENSE`, `desktop/LICENSE` and `docker/LICENSE` are still the AGPL text and re-vendor
`licenses/RECEIPT-WRANGLER-LICENSE` if it changed. Record digests in `UPSTREAM.md` and
`THIRD_PARTY_NOTICES.md`.

## Upgrade procedure

1. Update `ARG RECEIPT_WRANGLER_IMAGE=` (tag **and** digest) and `ARG RECEIPT_WRANGLER_VERSION=`.
2. Re-check the bootstrap's assumptions against upstream: the default credentials in
   `api/internal/commands/constants.go`, the login route, and `POST /api/user/{id}/resetPassword`
   in `api/internal/routers/user.go`. If any changed, update `scripts/bootstrap-admin.sh` — the
   smoke test's "upstream default admin/admin rejected" assertion is the safety net.
3. `docker compose build && tests/static.sh && tests/smoke.sh && tests/persistence.sh`.
4. Upgrade test against existing data: run the previous release against a volume that has a receipt
   and an image, then start the new image on the same volume and database; confirm migrations
   succeed, login works, and the receipt and its image are intact.
5. Update README versions, UPSTREAM.md, THIRD_PARTY_NOTICES.md; commit; wait for CI.
6. Tag `vA.B.C`, push, watch `publish-image`, record the digest.
7. Anonymous pull check with an empty Docker config, then run the smoke suite against that image.
8. `gh release create vA.B.C --notes-file …` (upstream version, digests, architectures, migration
   notes, test evidence; no AI attribution).
9. Update the `receipt-wrangler` service image in the Railway template composer (Railway rejects
   `@sha256` references, so use the version tag), save, run a clean-room deploy, then consider the
   template updated.

## Disk and CI notes

The upstream image is ~8.2 GB. The GitHub-hosted runner needs the "Free disk space" step in both
workflows; without it the build runs out of space. Local runs need roughly 20 GB free.

## Railway template operations

- Metadata: `npx -y @railway/cli@latest templates update <TEMPLATE_ID> --category Other --description "…" --readme-file RAILWAY_TEMPLATE.md --json`
- Service configuration lives in the dashboard composer; verify afterwards with the public API
  `template(id) { serializedConfig }` using the CLI token.
- Clean-room deploy: new project, `railway deploy -t <CODE>`, wait for SUCCESS, read the generated
  `RW_ADMIN_PASSWORD` with `railway variable list --json` (never print it), run
  `tests/railway-smoke.sh https://<domain>`, then delete the project by ID.
- Rollback: point the template's service image back to the last known-good tag.
- Unpublish (keeps user deployments): `npx -y @railway/cli@latest templates unpublish <ID> --yes --json`.

## Cadence

Weekly glance at upstream releases and the Railway template queue; monthly full review; act on
upstream releases within a week.
