# Third-party notices

The original wrapper code in this repository (Dockerfile, `scripts/`, tests, CI, documentation) is
MIT licensed (`LICENSE`). The published image redistributes the upstream Receipt Wrangler image
unmodified, plus those scripts and the `jq` package.

## Receipt Wrangler — AGPL-3.0-only

| Item | Value |
|---|---|
| Component | Receipt Wrangler (Go API, Angular web app, nginx configuration) |
| Version | v7.1.0 |
| Source | https://github.com/Receipt-Wrangler/receipt-wrangler/tree/v7.1.0 |
| Image | `docker.io/noah231515/receipt-wrangler:v7.1.0@sha256:3a3a66266927adbecdca3815eba386b99bca519f02ebd700ae55a7690930bfa0` |
| Licence | GNU Affero General Public License v3.0 only — full text in `licenses/RECEIPT-WRANGLER-LICENSE` and in the image at `/usr/share/licenses/receipt-wrangler-railway/RECEIPT-WRANGLER-LICENSE` |

**Corresponding source.** The image published by this repository contains Receipt Wrangler exactly
as upstream built it at the tag above; the complete corresponding source is the upstream tree
linked above. The wrapper adds only `scripts/entrypoint.sh`, `scripts/bootstrap-admin.sh` and the
`jq` package, all present in this repository. If you deploy this template and let other people use
it over a network, AGPL §13 makes you responsible for offering them that source; linking to the
upstream tag and to this repository satisfies it as long as you do not modify the application.

## Other components (as shipped inside the upstream image)

| Component | Licence | Source |
|---|---|---|
| Go runtime and standard library | BSD-3-Clause | https://go.dev |
| nginx | BSD-2-Clause | https://nginx.org |
| Tesseract OCR | Apache-2.0 | https://github.com/tesseract-ocr/tesseract |
| ImageMagick | ImageMagick licence (Apache-2.0 compatible) | https://imagemagick.org |
| Chromium (PDF rendering) | BSD-3-Clause and others | https://www.chromium.org |
| Python runtime and packages in the bundled venv | PSF and various OSI licences | as shipped upstream |
| Angular and npm dependencies of the web app | MIT and various OSI licences | `desktop/package-lock.json` upstream |
| Debian trixie base packages | various (GPL, LGPL, MIT, BSD) | https://www.debian.org |
| `jq` (added by this wrapper) | MIT | https://jqlang.org |

Test fixtures contain no third-party content: `tests/fixtures/make-receipt.py` draws a synthetic
receipt image from a built-in bitmap font at test time.

"Receipt Wrangler" is the upstream project's name. This template is community maintained and is
not affiliated with the Receipt Wrangler project or Railway.
