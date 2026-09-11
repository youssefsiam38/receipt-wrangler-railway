# syntax=docker/dockerfile:1
#
# receipt-wrangler-railway: thin wrapper around the official Receipt Wrangler monolith image.
# It replaces the built-in admin/admin bootstrap account's password with a generated one before
# the public listener (nginx) starts, and validates required variables. Application code,
# nginx configuration, OCR tooling and the API binary are unchanged.
#
# Base image is pinned by tag AND digest. Update RECEIPT_WRANGLER_IMAGE and RECEIPT_WRANGLER_VERSION together.
ARG RECEIPT_WRANGLER_IMAGE=docker.io/noah231515/receipt-wrangler:v7.1.0@sha256:3a3a66266927adbecdca3815eba386b99bca519f02ebd700ae55a7690930bfa0

FROM ${RECEIPT_WRANGLER_IMAGE}

ARG RECEIPT_WRANGLER_VERSION=7.1.0
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

# jq is used by the bootstrap script to build and read JSON safely (no shell quoting of secrets).
RUN apt-get update && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*

# Upstream's server block listens on IPv4 only; add an IPv6 listener for platforms that reach
# containers over IPv6. Both listeners proxy to the same API on localhost:8081.
COPY scripts/nginx-dual-stack.conf /etc/nginx/conf.d/zz-dual-stack.conf
RUN nginx -t

COPY licenses/ /usr/share/licenses/receipt-wrangler-railway/
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/receipt-wrangler-railway-entrypoint
COPY --chmod=0755 scripts/bootstrap-admin.sh /usr/local/bin/receipt-wrangler-railway-bootstrap

LABEL org.opencontainers.image.title="receipt-wrangler-railway" \
      org.opencontainers.image.description="Community Railway wrapper for Receipt Wrangler (self-hosted receipt scanning and expense sharing). Not affiliated with the Receipt Wrangler project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/receipt-wrangler-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/receipt-wrangler-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/receipt-wrangler-railway#readme" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="docker.io/noah231515/receipt-wrangler:v${RECEIPT_WRANGLER_VERSION}" \
      io.receipt-wrangler-railway.upstream.version="${RECEIPT_WRANGLER_VERSION}"

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/receipt-wrangler-railway-entrypoint"]
