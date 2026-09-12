#!/usr/bin/env bash
set -euo pipefail
: "${OUT:?OUT is required}"
RAW="$OUT/raw"
RESULTS="$OUT/results.tsv"
mkdir -p "$RAW"
printf "id	category	result	expected	actual	detail
" > "$RESULTS"

record() {
  local id="$1" category="$2" result="$3" expected="$4" actual="$5" detail="$6"
  expected="${expected//$'\t'/ }"; actual="${actual//$'\t'/ }"; detail="${detail//$'\t'/ }"
  printf "%s	%s	%s	%s	%s	%s
" "$id" "$category" "$result" "$expected" "$actual" "$detail" >> "$RESULTS"
}

aws sts get-caller-identity > "$RAW/caller_identity.json"
aws ec2 describe-vpcs --vpc-ids "$SECURE_VPC_ID" > "$RAW/vpc.json"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$SECURE_VPC_ID" > "$RAW/subnets.json"
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$SECURE_VPC_ID" > "$RAW/route_tables.json"
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$SECURE_VPC_ID" > "$RAW/internet_gateways.json"
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$SECURE_VPC_ID" > "$RAW/nat_gateways.json"
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$SECURE_VPC_ID" > "$RAW/vpc_endpoints.json"
aws ec2 describe-instances --instance-ids "$CLAUDE_INSTANCE_ID" > "$RAW/instance.json"
aws efs describe-file-systems --file-system-id "$EFS_FILE_SYSTEM_ID" > "$RAW/efs.json"
aws efs describe-access-points --file-system-id "$EFS_FILE_SYSTEM_ID" > "$RAW/efs_access_points.json"
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$BEDROCK_VPCE_ID" > "$RAW/bedrock_vpce.json"

IGW_COUNT="$(python3 - "$RAW/internet_gateways.json" <<'PY'
import json,sys
print(len(json.load(open(sys.argv[1]))["InternetGateways"]))
PY
)"
[[ "$IGW_COUNT" == "0" ]] && record NET-001 Network PASS "No Internet Gateway attached" "0 IGW" "Secure VPC has no IGW" || record NET-001 Network FAIL "No Internet Gateway attached" "$IGW_COUNT IGW" "Internet egress path may exist"

NAT_COUNT="$(python3 - "$RAW/nat_gateways.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))["NatGateways"]
print(sum(1 for n in x if n.get("State") not in ("deleted","deleting")))
PY
)"
[[ "$NAT_COUNT" == "0" ]] && record NET-002 Network PASS "No NAT Gateway in Secure VPC" "0 active NAT" "No managed NAT egress" || record NET-002 Network FAIL "No NAT Gateway in Secure VPC" "$NAT_COUNT active NAT" "Unexpected NAT gateway"

DEFAULT_ROUTES="$(python3 - "$RAW/route_tables.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
bad=[]
for rt in d["RouteTables"]:
    for r in rt.get("Routes",[]):
        if r.get("DestinationCidrBlock")=="0.0.0.0/0" or r.get("DestinationIpv6CidrBlock")=="::/0":
            bad.append(r)
print(len(bad))
PY
)"
[[ "$DEFAULT_ROUTES" == "0" ]] && record NET-003 Network PASS "No default Internet route" "0 default routes" "No 0.0.0.0/0 or ::/0 route" || record NET-003 Network FAIL "No default Internet route" "$DEFAULT_ROUTES default routes" "Review route_tables.json"

PUBLIC_IP="$(python3 - "$RAW/instance.json" <<'PY'
import json,sys
i=json.load(open(sys.argv[1]))["Reservations"][0]["Instances"][0]
print(i.get("PublicIpAddress",""))
PY
)"
[[ -z "$PUBLIC_IP" ]] && record EC2-001 Compute PASS "No public IPv4" "none" "Claude host has no public IP" || record EC2-001 Compute FAIL "No public IPv4" "$PUBLIC_IP" "Public IP must be removed"

read -r VPCE_SERVICE VPCE_STATE < <(python3 - "$RAW/bedrock_vpce.json" <<'PY'
import json,sys
e=json.load(open(sys.argv[1]))["VpcEndpoints"][0]
print(e.get("ServiceName",""), e.get("State",""))
PY
)
if [[ "$VPCE_SERVICE" == *".bedrock-runtime" && "$VPCE_STATE" == "available" ]]; then
  record VPCE-001 PrivateLink PASS "Available Bedrock Runtime VPCE" "$VPCE_SERVICE ($VPCE_STATE)" "Bedrock endpoint is ready"
else
  record VPCE-001 PrivateLink FAIL "Available Bedrock Runtime VPCE" "$VPCE_SERVICE ($VPCE_STATE)" "Unexpected service/state"
fi

AP_COUNT="$(python3 - "$RAW/efs_access_points.json" <<'PY'
import json,sys
print(len(json.load(open(sys.argv[1]))["AccessPoints"]))
PY
)"
[[ "$AP_COUNT" -ge 10 ]] && record EFS-001 Storage PASS "At least 10 EFS Access Points" "$AP_COUNT" "Per-user access points present" || record EFS-001 Storage FAIL "At least 10 EFS Access Points" "$AP_COUNT" "Expected one access point per user"

COMMANDS=(
  "if curl -fsS --connect-timeout 5 https://github.com >/dev/null 2>&1; then echo INTERNET_GITHUB=REACHABLE; else echo INTERNET_GITHUB=BLOCKED; fi"
  "if curl -fsS --connect-timeout 5 https://pypi.org >/dev/null 2>&1; then echo INTERNET_PYPI=REACHABLE; else echo INTERNET_PYPI=BLOCKED; fi"
  "getent hosts bedrock-runtime.$AWS_REGION.amazonaws.com || true"
)
if [[ -n "${USER01:-}" && -n "${USER02:-}" ]]; then
  COMMANDS+=("if sudo -u '$USER01' test -r '/home/$USER02'; then echo USER_ISOLATION=FAILED; else echo USER_ISOLATION=PASS; fi")
fi

PARAMS="$(python3 - "${COMMANDS[@]}" <<'PY'
import json,sys
print(json.dumps({"commands":sys.argv[1:]}))
PY
)"
CMD_ID="$(aws ssm send-command --instance-ids "$CLAUDE_INSTANCE_ID" --document-name AWS-RunShellScript --parameters "$PARAMS" --query 'Command.CommandId' --output text)"
aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$CLAUDE_INSTANCE_ID" || true
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$CLAUDE_INSTANCE_ID" > "$RAW/ssm_behavior_checks.json"

python3 - "$RAW/ssm_behavior_checks.json" > "$RAW/ssm_behavior_checks.txt" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get("StandardOutputContent",""))
PY

grep -q "INTERNET_GITHUB=BLOCKED" "$RAW/ssm_behavior_checks.txt" && record EXF-001 Exfiltration PASS "Direct github.com blocked" "blocked" "Checked from Claude host" || record EXF-001 Exfiltration FAIL "Direct github.com blocked" "reachable/unknown" "Review SSM output"
grep -q "INTERNET_PYPI=BLOCKED" "$RAW/ssm_behavior_checks.txt" && record EXF-002 Exfiltration PASS "Direct pypi.org blocked" "blocked" "Checked from Claude host" || record EXF-002 Exfiltration FAIL "Direct pypi.org blocked" "reachable/unknown" "Review SSM output"
grep -Eq '([0-9]{1,3}\.){3}[0-9]{1,3}' "$RAW/ssm_behavior_checks.txt" && record DNS-001 DNS PASS "Bedrock hostname resolves" "resolved" "Inspect raw output for private IP" || record DNS-001 DNS FAIL "Bedrock hostname resolves" "not resolved" "Check VPCE Private DNS and VPC DNS settings"

if [[ -n "${USER01:-}" && -n "${USER02:-}" ]]; then
  grep -q "USER_ISOLATION=PASS" "$RAW/ssm_behavior_checks.txt" && record ISO-001 Isolation PASS "$USER01 cannot read $USER02 home" "denied" "Basic user isolation works" || record ISO-001 Isolation FAIL "$USER01 cannot read $USER02 home" "readable/unknown" "Review EFS mount/access point and permissions"
fi

(
  cd "$OUT"
  find raw -type f -print0 | sort -z | xargs -0 sha256sum
  sha256sum results.tsv
) > "$OUT/SHA256SUMS"

echo "Evidence collected into $OUT"
