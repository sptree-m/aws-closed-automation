#!/usr/bin/env bash
set -euo pipefail
CONFIG="${USERS_CONFIG:-config/users.yaml}"
python3 - "$CONFIG" <<'PY'
import sys, pathlib
try:
    import yaml
except ImportError:
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    raise SystemExit(3)
p=pathlib.Path(sys.argv[1])
if not p.exists():
    print("No users configured")
    raise SystemExit(0)
data=yaml.safe_load(p.read_text()) or {"users":[]}
print(f"{'USERNAME':<18} {'UID':<8} {'ENABLED':<8} DISPLAY")
for u in data.get("users",[]):
    print(f"{u['username']:<18} {u['uid']:<8} {str(u.get('enabled',True)):<8} {u.get('display_name','')}")
PY
