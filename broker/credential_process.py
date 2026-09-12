#!/usr/bin/env python3
import json
import os
import socket
import sys

SOCKET_PATH = os.environ.get("BROKER_SOCKET", "/run/claude-credential-broker.sock")

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(SOCKET_PATH)
buf = b""
while not buf.endswith(b"\n"):
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
s.close()

resp = json.loads(buf.decode())
if not resp.get("ok"):
    print(resp.get("error", "credential broker failed"), file=sys.stderr)
    sys.exit(1)

print(json.dumps(resp["credentials"]))
