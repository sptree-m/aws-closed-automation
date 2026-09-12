#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ -f .env ]] && source .env
: "${AWS_REGION:?AWS_REGION is required}"
: "${SECURE_VPC_ID:?SECURE_VPC_ID is required}"
: "${CLAUDE_INSTANCE_ID:?CLAUDE_INSTANCE_ID is required}"
: "${EFS_FILE_SYSTEM_ID:?EFS_FILE_SYSTEM_ID is required}"
: "${BEDROCK_VPCE_ID:?BEDROCK_VPCE_ID is required}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="evidence/$STAMP"
mkdir -p "$OUT/raw"
export OUT AWS_DEFAULT_REGION="$AWS_REGION"
bash scripts/collect_evidence.sh
if [[ -n "${USER01:-}" ]]; then bash scripts/collect_identity_evidence.sh; fi
python3 scripts/generate_report.py "$OUT"
if [[ -n "${EVIDENCE_BUCKET:-}" ]]; then bash scripts/upload_evidence.sh "$OUT"; fi
echo "Evidence complete: $OUT"
echo "Report: $OUT/report.html"
