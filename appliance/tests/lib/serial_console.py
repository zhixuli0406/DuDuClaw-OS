#!/usr/bin/env python3
"""Expect-style serial console driver for the appliance VM — committed twin
of the gitignored `appliance/.vm/inject/serial_expect.py` (see that file's
own module doc for the login/typeahead lessons this logic embeds; ported
here near-verbatim so it survives a fresh checkout instead of living only
in host-local scratch state).

Keeps ONE connection open and only sends after the expected prompt has
actually arrived — required because login(1) discards typeahead and PAM
adds a failure delay, so a fixed-wait "send now, hope it landed after a
prompt" approach intermittently feeds commands into a `Password:` prompt.

`DEFAULT_ROOT_PASSWORD = "duduclaw"` is the project-wide convention
password every `appliance/tests/ab-update/*_probe.py` script defaults to —
kept identical here rather than inventing a second convention. **It only
works on a disk that has actually had it injected** (`ab-update/
inject-binaries.sh`'s `AB_ROOT_PASSWORD`, or a manual `set_root_pw.awk`
round). Live-checked against a fresh `cp -c` clone of the CURRENT
`appliance/.vm/duduclaw-os-vm.raw` on 2026-08-24: `serial-getty@ttyAMA0.
service` IS enabled and answers a `login:` prompt, but root has **no**
password set at all, so `"duduclaw"` (or any password) is rejected — PAM's
own audit line confirms `res=failed`. This directly matches
`commercial/docs/DESIGN-ab-update-rollback-2026-08.md` §11.6's same-day
finding: "出貨 image 沒有設任何 root 密碼...`.vm/inject/set_root_pw.awk`
是上一輪手打的殘骸、沒有呼叫端" (the shipping image sets no root password
at all; the old awk-based patch script is a stale remnant with no caller
today). An EARLIER round's note in `crates/duduclaw-comp/BUILD.md` ("three
things were changed") describes a DIFFERENT working copy that at THAT time
had a password baked in — that state did not survive into the disk as it
exists now (rebuilt/re-cloned from pristine since). Bottom line: don't
trust either doc's claim about a specific disk's credential state over a
live probe — `ensure_shell` returning `False` on a stock clone is the
expected, correct answer, not a bug in this module."""
from __future__ import annotations

import re
import socket
import time

DEFAULT_ROOT_PASSWORD = "duduclaw"


class SerialConsole:
    def __init__(self, host: str, port: int, connect_timeout: float = 10.0):
        self.sock = socket.create_connection((host, port), timeout=connect_timeout)
        self.sock.settimeout(0.4)
        self.buf = b""

    def __enter__(self) -> "SerialConsole":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass

    def read_until(self, patterns: list[bytes], timeout: float) -> bytes | None:
        """Accumulate until any pattern appears in the tail; return the one
        that matched, or None on timeout."""
        end = time.time() + timeout
        while time.time() < end:
            try:
                chunk = self.sock.recv(65536)
                if chunk:
                    self.buf += chunk
            except socket.timeout:
                pass
            tail = self.buf[-4096:]
            for p in patterns:
                if p in tail:
                    return p
        return None

    def send(self, text: str) -> None:
        self.sock.sendall(text.encode())

    def drain(self, secs: float = 0.8) -> None:
        end = time.time() + secs
        while time.time() < end:
            try:
                chunk = self.sock.recv(65536)
                if chunk:
                    self.buf += chunk
            except socket.timeout:
                pass

    def run(self, command: str, timeout: float = 30.0) -> str:
        """Run one command, bracketed by unique markers so we never confuse
        an echo of the command line with its output."""
        tag = f"M{int(time.time() * 1000) % 100000000}"
        self.buf = b""
        # Markers are quote-split in the TYPED line (`{tag}'-E'`) so the
        # tty's echo of the command never itself contains the literal
        # `{tag}-E` we wait for — only the shell's actual output does.
        self.send(f"echo {tag}'-B'; {command}; echo {tag}'-E'\n")
        got = self.read_until([f"{tag}-E".encode()], timeout)
        text = self.buf.decode(errors="replace")
        text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)  # strip ANSI control sequences
        begin, end_m = f"{tag}-B", f"{tag}-E"
        lines = text.splitlines()
        out: list[str] = []
        capturing = False
        for ln in lines:
            s = ln.strip()
            if s == begin:
                capturing = True
                continue
            if s == end_m:
                capturing = False
                break
            if capturing:
                out.append(ln)
        if got is None:
            out.append(f"[serial_console: TIMEOUT after {timeout}s]")
        return "\n".join(out)


def ensure_shell(console: SerialConsole, password: str = DEFAULT_ROOT_PASSWORD, attempts: int = 3) -> bool:
    """Get to a root shell no matter which prompt the console sits at.
    Idempotent — safe to call when a shell is already live (probes first,
    skips login when the probe answers)."""
    for attempt in range(attempts):
        if _ensure_shell_once(console, password):
            return True
        if attempt < attempts - 1:
            time.sleep(3)
    return False


def _ensure_shell_once(console: SerialConsole, password: str) -> bool:
    console.buf = b""
    console.send("\x15\n")  # kill-line then newline — clears half-typed junk
    m = console.read_until([b"login:", b"Password:", b"#"], 8)
    if m == b"#":
        return True
    if m == b"Password:":
        # Unknown state — fail it with an empty password, wait out PAM.
        console.send("\n")
        console.read_until([b"login:"], 15)
        m = b"login:"
    if m == b"login:":
        console.send("root\n")
        if console.read_until([b"Password:"], 10) is None:
            return False
        console.send(password + "\n")
        got = console.read_until([b"#", b"login:"], 20)
        return got == b"#"
    return False
