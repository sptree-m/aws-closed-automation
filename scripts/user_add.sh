#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${1:?usage: user_add.sh <username> <uid> [display_name]}"
USER_UID="${2:?usage: user_add.sh <username> <uid> [display_name]}"
DISPLAY_NAME="${3:-$USER_NAME}"
USER_GID="$USER_UID"

if ! [[ "$USER_NAME" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]; then
  echo "Invalid username: $USER_NAME" >&2
  exit 2
fi
if ! [[ "$USER_UID" =~ ^[0-9]+$ ]] || (( USER_UID < 10000 || USER_UID > 60000 )); then
  echo "UID must be between 10000 and 60000" >&2
  exit 2
fi

CONFIG="${USERS_CONFIG:-config/users.yaml}"
mkdir -p "$(dirname "$CONFIG")"

python3 - "$CONFIG" "$USER_NAME" "$USER_UID" "$USER_GID" "$DISPLAY_NAME" <<'PY'
import sys, pathlib
try:
    import yaml
except ImportError:
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    raise SystemExit(3)

p=pathlib.Path(sys.argv[1])
username=sys.argv[2]
uid=int(sys.argv[3]); gid=int(sys.argv[4]); display=sys.argv[5]

data={"users":[]}
if p.exists():
    data=yaml.safe_load(p.read_text()) or {"users":[]}
users=data.setdefault("users",[])

if any(u.get("username")==username for u in users):
    raise SystemExit(f"user already exists: {username}")
if any(int(u.get("uid",-1))==uid for u in users):
    raise SystemExit(f"uid already exists: {uid}")

users.append({
    "username": username,
    "uid": uid,
    "gid": gid,
    "enabled": True,
    "display_name": display,
    "bedrock_tag": username,
})
users.sort(key=lambda x:int(x["uid"]))
p.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
print(f"added {username} to {p}")
PY
