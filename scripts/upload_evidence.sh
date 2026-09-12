#!/usr/bin/env bash
set -euo pipefail
OUT="${1:?usage: upload_evidence.sh evidence/<timestamp>}"
: "${EVIDENCE_BUCKET:?EVIDENCE_BUCKET is required}"
STAMP="$(basename "$OUT")"
PREFIX="${EVIDENCE_PREFIX:-claude-closed-env}/$STAMP"
ARGS=(--recursive)
if [[ -n "${EVIDENCE_KMS_KEY_ARN:-}" ]]; then
  ARGS+=(--sse aws:kms --sse-kms-key-id "$EVIDENCE_KMS_KEY_ARN")
else
  ARGS+=(--sse AES256)
fi
aws s3 cp "$OUT" "s3://$EVIDENCE_BUCKET/$PREFIX/" "${ARGS[@]}"
echo "Uploaded evidence to s3://$EVIDENCE_BUCKET/$PREFIX/"
