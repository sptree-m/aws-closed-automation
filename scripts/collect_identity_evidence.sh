#!/usr/bin/env bash
set -euo pipefail
: "${OUT:?OUT is required}"
: "${CLAUDE_INSTANCE_ID:?CLAUDE_INSTANCE_ID is required}"
: "${USER01:?USER01 is required}"

RAW="$OUT/raw"
mkdir -p "$RAW"

PARAMS="$(python3 - "$USER01" <<'PY'
import json,sys
u=sys.argv[1]
cmds=[
 f"if sudo -u '{u}' curl -fsS --connect-timeout 2 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then echo IMDS_USER=REACHABLE; else echo IMDS_USER=BLOCKED; fi",
 f"if sudo -u '{u}' /usr/local/bin/claude-credential-process >/tmp/claude-creds.json 2>/dev/null; then python3 -c \"import json; d=json.load(open('/tmp/claude-creds.json')); print('BROKER_CREDENTIALS=OK' if d.get('AccessKeyId') else 'BROKER_CREDENTIALS=FAILED')\"; else echo BROKER_CREDENTIALS=FAILED; fi",
]
print(json.dumps({"commands":cmds}))
PY
)"

CMD_ID="$(aws ssm send-command   --instance-ids "$CLAUDE_INSTANCE_ID"   --document-name AWS-RunShellScript   --parameters "$PARAMS"   --query 'Command.CommandId' --output text)"

aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$CLAUDE_INSTANCE_ID" || true
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$CLAUDE_INSTANCE_ID" > "$RAW/identity_checks.json"

python3 - "$RAW/identity_checks.json" > "$RAW/identity_checks.txt" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get("StandardOutputContent",""))
PY

if grep -q "IMDS_USER=BLOCKED" "$RAW/identity_checks.txt"; then
  echo -e "IAM-001\tIdentity\tPASS\tNormal user cannot reach EC2 IMDS\tblocked\tHost firewall protects instance-profile credentials" >> "$OUT/results.tsv"
else
  echo -e "IAM-001\tIdentity\tFAIL\tNormal user cannot reach EC2 IMDS\treachable/unknown\tReview nftables IMDS guard" >> "$OUT/results.tsv"
fi

if grep -q "BROKER_CREDENTIALS=OK" "$RAW/identity_checks.txt"; then
  echo -e "IAM-002\tIdentity\tPASS\tCredential broker issues short-lived credentials\tissued\tUID-bound broker responded" >> "$OUT/results.tsv"
else
  echo -e "IAM-002\tIdentity\tFAIL\tCredential broker issues short-lived credentials\tfailed/unknown\tReview broker, STS connectivity and role trust" >> "$OUT/results.tsv"
fi
