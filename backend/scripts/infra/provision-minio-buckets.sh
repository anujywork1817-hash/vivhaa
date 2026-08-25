#!/usr/bin/env bash
# Provisions the MinIO buckets the API requires in prod/staging.
#
# Why this exists: cmd/api/main.go only calls s3Client.EnsureBucket() /
# EnsureDocsBucket() when APP_ENV=dev, by design — prod/staging are
# expected to have buckets provisioned by infra tooling ahead of time.
# On the 2026-08-24 Mumbai deployment nobody actually did that: the
# public "matrimony-photos" bucket happened to exist from an earlier
# dev-mode run, but the private "matrimony-verification-docs" bucket
# never did, and every identity-verification upload failed with a
# generic "internal_error" until this was traced to a missing bucket.
#
# This script is the explicit provisioning step that replaces the
# ad-hoc `mc mb` command run by hand during that incident. It is safe
# to re-run against an environment that already has the buckets — `mc
# mb` is a no-op if the bucket exists, and `mc anonymous set` just
# re-asserts the policy.
#
# Run this from a host that can reach the MinIO container directly
# (e.g. via SSH to the supporting-services EC2 box), with `mc` already
# configured, OR set MC_HOST_local to point `mc` at the endpoint:
#   MC_HOST_local=http://ACCESS_KEY:SECRET_KEY@172.31.5.27:59000 \
#     ./provision-minio-buckets.sh

set -euo pipefail

ALIAS="${MC_ALIAS:-local}"
PUBLIC_BUCKET="${S3_BUCKET:-matrimony-photos}"
DOCS_BUCKET="${S3_DOCS_BUCKET:-matrimony-verification-docs}"

echo "Ensuring public bucket: ${PUBLIC_BUCKET}"
mc mb --ignore-existing "${ALIAS}/${PUBLIC_BUCKET}"
mc anonymous set download "${ALIAS}/${PUBLIC_BUCKET}"

echo "Ensuring private verification-docs bucket: ${DOCS_BUCKET}"
mc mb --ignore-existing "${ALIAS}/${DOCS_BUCKET}"
mc anonymous set none "${ALIAS}/${DOCS_BUCKET}"

echo "Done. Current buckets:"
mc ls "${ALIAS}"
