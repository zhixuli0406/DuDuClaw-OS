#!/usr/bin/env python3
"""Host-side functional test for duduclaw-health-check.sh (H3c).

Stands up a fake gateway `/healthz` and a fake duduclaw-sysd unix socket, then
runs the REAL script against them in six scenarios. No VM, no root, no image —
runs anywhere bash + python3 + curl exist, in about ten seconds.

Why this exists as its own test: that script's exit code is the entire input
to "should this boot be blessed", and both directions of a wrong answer are
expensive — a false pass blesses a broken update (losing the rollback), a
false failure retires a version that was fine. The VM rounds prove the wiring;
this proves the decision logic, including the cases a VM round cannot
conveniently produce (a stale socket inode with no listener, a 200 response
whose `ok` is false, a missing config.toml).

Usage:  python3 appliance/tests/ab-update/health_check_test.py
"""
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

SCRIPT = str(
    Path(__file__).resolve().parent.parent.parent
    / "mkosi.extra/usr/local/sbin/duduclaw-health-check.sh"
)

STATE = {"code": 200, "body": {"ok": True, "service": "duduclaw-gateway"}}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/healthz":
            self.send_response(404)
            self.end_headers()
            return
        payload = json.dumps(STATE["body"], separators=(",", ":")).encode()
        self.send_response(STATE["code"])
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *a):
        pass


def unix_server(path, stop, reply=True):
    """Stand in for duduclaw-sysd. With reply=True it answers the way the real
    daemon does to a probe from root (uid != the configured peer): one line of
    structured JSON, verbatim from a live appliance VM. With reply=False it
    accepts and hangs up, which is the weaker tier the gate must still pass."""
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path)
    srv.listen(8)
    srv.settimeout(0.3)
    while not stop.is_set():
        try:
            conn, _ = srv.accept()
            if reply:
                conn.sendall(b'{"audit_id":"t","ok":false,'
                             b'"error":{"kind":"unauthorized","message":"caller uid"}}\n')
            conn.close()
        except socket.timeout:
            continue
        except OSError:
            break
    srv.close()


def run(env_extra, timeout=40):
    env = dict(os.environ)
    env.update(env_extra)
    t0 = time.time()
    p = subprocess.run(["bash", SCRIPT], env=env, capture_output=True, text=True,
                       timeout=timeout)
    return p.returncode, p.stdout + p.stderr, time.time() - t0


def main():
    tmp = tempfile.mkdtemp()
    home = os.path.join(tmp, "home")
    os.makedirs(home)
    httpd = HTTPServer(("127.0.0.1", 0), Handler)
    port = httpd.server_address[1]
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    with open(os.path.join(home, "config.toml"), "w") as f:
        f.write(f"[odoo]\nport = 8069\n\n[gateway]\nbind = \"0.0.0.0\"\nport = {port}\n")

    sock_path = os.path.join(tmp, "sysd.sock")
    stop = threading.Event()
    threading.Thread(target=unix_server, args=(sock_path, stop), daemon=True).start()
    time.sleep(0.5)

    base = {"DUDUCLAW_HOME": home, "DUDUCLAW_SYSD_SOCKET": sock_path,
            "DUDUCLAW_HEALTH_TIMEOUT": "6", "DUDUCLAW_HEALTH_POLL_INTERVAL": "1"}
    failures = []

    def check(name, cond, detail):
        print(f"  {'PASS' if cond else 'FAIL'}  {name}")
        if not cond:
            failures.append(f"{name}: {detail}")

    print("[1] healthy gateway + live sysd socket -> exit 0")
    rc, out, dt = run(base)
    check("exit 0", rc == 0, f"rc={rc}\n{out}")
    check("recorded the daemon's own answer, not just a connect",
          "daemon answered the probe" in out, out)
    check("used the config.toml port (section-aware parse)", f":{port}/healthz" in out, out)
    check("returned fast (no needless waiting)", dt < 5, f"{dt:.1f}s")

    print("[2] gateway returns 503 (stalled scheduler) -> exit 1 after budget")
    STATE["code"], STATE["body"] = 503, {"ok": False, "schedulers": {"cron_stalled": True}}
    rc, out, dt = run(base)
    check("exit 1", rc == 1, f"rc={rc}\n{out}")
    check("spent the whole budget before giving up", dt >= 6, f"{dt:.1f}s")
    check("reported the http code", "http=503" in out, out)

    print("[3] gateway 200 but ok:false (degraded) -> exit 1, not silently blessed")
    STATE["code"], STATE["body"] = 200, {"ok": False}
    rc, out, dt = run(base)
    check("exit 1", rc == 1, f"rc={rc}\n{out}")
    check("said why", "ok!=true" in out, out)

    print("[4] gateway healthy but sysd socket gone -> exit 1")
    STATE["code"], STATE["body"] = 200, {"ok": True}
    stop.set()
    time.sleep(0.5)
    os.unlink(sock_path)
    rc, out, dt = run(base)
    check("exit 1", rc == 1, f"rc={rc}\n{out}")
    check("named the missing socket", "missing" in out, out)

    print("[5] stale socket file, nothing listening -> exit 1 (connect refused)")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(sock_path)
    s.close()  # leaves the socket inode behind with no listener
    rc, out, dt = run(base)
    check("exit 1", rc == 1, f"rc={rc}\n{out}")
    check("distinguished 'refused' from 'missing'", "connect refused" in out, out)

    print("[6] no config.toml at all -> falls back to port 18789")
    rc, out, dt = run({**base, "DUDUCLAW_HOME": os.path.join(tmp, "nope"),
                       "DUDUCLAW_HEALTH_TIMEOUT": "2"})
    check("used default port", ":18789/healthz" in out, out)

    httpd.shutdown()
    print()
    if failures:
        print(f"HEALTH-CHECK SCRIPT: FAIL ({len(failures)})")
        for f in failures:
            print("  -", f)
        return 1
    print("HEALTH-CHECK SCRIPT: PASS (6 scenarios)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
