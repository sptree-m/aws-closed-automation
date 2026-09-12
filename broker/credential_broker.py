#!/usr/bin/env python3
import json
import os
import socket
import struct
import sys
import time
from pathlib import Path

import boto3

SOCKET_PATH = os.environ.get("BROKER_SOCKET", "/run/claude-credential-broker.sock")
MAP_PATH = os.environ.get("BROKER_MAP", "/etc/claude-credential-broker/users.json")
DURATION = int(os.environ.get("BROKER_DURATION", "3600"))


def load_map():
    data = json.loads(Path(MAP_PATH).read_text())
    return {int(k): v for k, v in data["users"].items() if v.get("enabled", True)}


def peer_uid(conn):
    # Linux SO_PEERCRED -> struct ucred { pid_t pid; uid_t uid; gid_t gid; }
    raw = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    _pid, uid, _gid = struct.unpack("3i", raw)
    return uid


def issue(uid):
    users = load_map()
    if uid not in users:
        raise PermissionError(f"UID {uid} is not authorized")

    u = users[uid]
    username = u["username"]
    role_arn = u["role_arn"]

    sts = boto3.client("sts")
    resp = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=f"claude-{username}",
        DurationSeconds=DURATION,
        SourceIdentity=username,
        Tags=[
            {"Key": "ClaudeUser", "Value": username},
            {"Key": "LinuxUID", "Value": str(uid)},
        ],
    )
    c = resp["Credentials"]
    return {
        "Version": 1,
        "AccessKeyId": c["AccessKeyId"],
        "SecretAccessKey": c["SecretAccessKey"],
        "SessionToken": c["SessionToken"],
        "Expiration": c["Expiration"].isoformat(),
    }


def main():
    path = Path(SOCKET_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        path.unlink()
    except FileNotFoundError:
        pass

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(str(path))
    os.chmod(path, 0o666)
    s.listen(64)

    while True:
        conn, _ = s.accept()
        with conn:
            try:
                uid = peer_uid(conn)
                payload = issue(uid)
                out = {"ok": True, "credentials": payload}
            except Exception as e:
                out = {"ok": False, "error": str(e)}
            conn.sendall((json.dumps(out) + "\n").encode())


if __name__ == "__main__":
    main()
