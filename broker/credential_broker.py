#!/usr/bin/env python3
import json
import os
import socket
import struct
import subprocess
from pathlib import Path

SOCKET_PATH = os.environ.get("BROKER_SOCKET", "/run/claude-credential-broker.sock")
MAP_PATH = os.environ.get("BROKER_MAP", "/etc/claude-credential-broker/users.json")
DURATION = int(os.environ.get("BROKER_DURATION", "3600"))

def load_map():
    data = json.loads(Path(MAP_PATH).read_text())
    return {int(k): v for k, v in data["users"].items() if v.get("enabled", True) and v.get("role_arn")}

def peer_uid(conn):
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
    cmd = [
        "aws","sts","assume-role",
        "--role-arn",role_arn,
        "--role-session-name",f"claude-{username}",
        "--duration-seconds",str(DURATION),
        "--source-identity",username,
        "--tags",f"Key=ClaudeUser,Value={username}",f"Key=LinuxUID,Value={uid}",
        "--output","json"
    ]
    resp=json.loads(subprocess.check_output(cmd, text=True))
    c=resp["Credentials"]
    return {
        "Version":1,
        "AccessKeyId":c["AccessKeyId"],
        "SecretAccessKey":c["SecretAccessKey"],
        "SessionToken":c["SessionToken"],
        "Expiration":c["Expiration"]
    }

def main():
    path=Path(SOCKET_PATH)
    path.parent.mkdir(parents=True,exist_ok=True)
    try: path.unlink()
    except FileNotFoundError: pass
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    s.bind(str(path))
    os.chmod(path,0o666)
    s.listen(64)
    while True:
        conn,_=s.accept()
        with conn:
            try:
                uid=peer_uid(conn)
                out={"ok":True,"credentials":issue(uid)}
            except Exception as e:
                out={"ok":False,"error":str(e)}
            conn.sendall((json.dumps(out)+"\n").encode())

if __name__=="__main__":
    main()
