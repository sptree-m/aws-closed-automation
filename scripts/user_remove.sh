#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${1:?usage: user_remove.sh <username> [--purge]}"
MODE="${2:-}"
CONFIG="${USERS_CONFIG:-config/users.yaml}"

python3 - "$CONFIG" "$USER_NAME" "$MODE" <<'PY'
import sys, pathlib
try:
    import yaml
except ImportError:
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    raise SystemExit(3)

p=pathlib.Path(sys.argv[1])
username=sys.argv[2]
mode=sys.argv[3]

if not p.exists():
    raise SystemExit(f"config not found: {p}")
data=yaml.safe_load(p.read_text()) or {"users":[]}
users=data.get("users",[])
target=next((u for u in users if u.get("username")==username),None)
if not target:
    raise SystemExit(f"user not found: {username}")

if mode=="--purge":
    data["users"]=[u for u in users if u.get("username")!=username]
    action="purged"
else:
    target["enabled"]=False
    action="disabled"

p.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
print(f"{action} {username} in {p}")
PY
