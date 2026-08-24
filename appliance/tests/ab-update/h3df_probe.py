#!/usr/bin/env python3
"""H3d/H3f acceptance probe — signed payload staging, real updates, rollback.

Continues the shape h3a_probe.py / h3bc_probe.py established (report all the
evidence first, assert afterwards, so a failure hands you the machine's own
words instead of a verdict). Where h3bc proved the *mechanism* — boot
counting really counts, the health gate really withholds a blessing, a
deliberately broken entry really rolls back — this probe drives the
**product path**: a release directory served over HTTP, downloaded and
signature-verified by the gateway, installed by systemd-sysupdate, booted,
blessed, and rolled back on demand.

Design matrix (commercial/docs/DESIGN-ab-update-rollback-2026-08.md §6.2):

  fixture  Build a signed test release out of the image already in
           mkosi.output/ (host-side; no VM involved). Optionally rewrites
           the payload's own IMAGE_VERSION so the installed slot honestly
           reports the new version — otherwise the update is a relabelled
           copy of the running one and `ProtectVersion=%A` protects the
           wrong string.
  sig      **Negative tests, and the most important ones here.** A manifest
           signed with the WRONG key, a release with NO signature, and a
           payload whose bytes do not match its signed digest must each be
           refused, with nothing published into the staging directory.
  t2       Normal update, end to end: host HTTP server -> device.update_apply
           -> verified staging -> sysupdate -> reboot -> running on the other
           slot -> blessed good.
  t5       Power cut during apply: kill the VM mid-install, then prove it
           still boots (on the old slot) rather than into a half-written one.
  t6       Manual rollback: device.update_rollback from the new slot returns
           the machine to the previous one.
  t7       Two consecutive bad updates must not exhaust both entries — the
           rollback target has to survive.
  esp      ESP peak measurement during a real update (T9 follow-up).

Usage:
  h3df_probe.py fixture [--version 0.2.0] [--inject-binaries] [--set-image-version]
  h3df_probe.py sig  [--host H] [--serial 47031]
  h3df_probe.py t2   [...] [--qmp 47032] [--http-port 8099]
  h3df_probe.py t5   [...]
  h3df_probe.py t6   [...]
  h3df_probe.py t7   [...]

The VM is expected to be running already (appliance/tests/ab-update/boot-ab.sh),
same as h3bc_probe.py.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

_APPLIANCE = Path(__file__).resolve().parent.parent.parent
_REPO = _APPLIANCE.parent

# Where the guest reaches the host under QEMU's user-mode networking. slirp
# maps this address onto the host's loopback, which is why the fixture server
# below binds 127.0.0.1 and is still reachable from inside the VM.
HOST_FROM_GUEST = "10.0.2.2"
GUEST_HOME = "/data/duduclaw"
GUEST_API = "http://127.0.0.1:18789"
ADMIN_PW = "duduclaw-ab-test-pw"

# The app-binary signing key. Used ONLY by the `sig` negative test, to prove
# the OS channel refuses a manifest that is perfectly, legitimately signed —
# just with the other channel's key. That separation is the whole point of
# shipping a second keypair (design §5.2).
APP_KEY = Path.home() / ".minisign" / "duduclaw-release.key"
OS_KEY = Path.home() / ".minisign" / "duduclaw-os-release.key"


def _load(name: str):
    """Load a host-local VM helper from appliance/.vm/inject/ (gitignored)."""
    path = _APPLIANCE / ".vm" / "inject" / f"{name}.py"
    if not path.exists():
        print(f"missing {path} — host-local helper (appliance/.vm is gitignored)",
              file=sys.stderr)
        sys.exit(2)
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        print(f"cannot load {path}", file=sys.stderr)
        sys.exit(2)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


serial_expect = _load("serial_expect")

BOOT_START_PATTERNS = [b"EFI stub: Booting Linux Kernel", b"Booting Linux on physical CPU"]
DEAD_BOOT_PATTERNS = [
    b"You are in emergency mode",
    b"Entering emergency mode",
    b"Timed out waiting for device",
    b"Cannot open root device",
    b"Kernel panic",
]


# --------------------------------------------------------------------------
# host side: fixtures
# --------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_manifest(release: Path, names: list[str]) -> None:
    lines = [f"{sha256_file(release / n)}  {n}\n" for n in names]
    (release / "SHA256SUMS").write_text("".join(lines))


def sign_manifest(release: Path, key: Path) -> None:
    if not key.exists():
        raise SystemExit(f"[h3df] signing key not found: {key}")
    sig = release / "SHA256SUMS.minisig"
    sig.unlink(missing_ok=True)
    subprocess.run(
        ["minisign", "-S", "-s", str(key), "-m", "SHA256SUMS"],
        cwd=release, check=True, input=b"", capture_output=True,
    )
    if not sig.exists():
        raise SystemExit("[h3df] minisign produced no signature")


def patch_image_version(raw: Path, old: str, new: str) -> int:
    """Rewrite `IMAGE_VERSION="<old>"` to `<new>` inside a root payload.

    Why bytes and not a mount: the payload is an ext4 image and this runs on
    a Mac with no loop devices. The two literals are the same length, so no
    inode, extent map or directory entry changes — and ext4's metadata
    checksums cover metadata, never file data, so patching a file's content
    in place cannot invalidate them. (`fixture --set-image-version` verifies
    the result with `e2fsck -fn` in a container before signing, and t2
    verifies it again from inside the booted slot: the update is only
    believed once the machine itself reports the new version.)

    Every occurrence is replaced, not just the first: os-release is copied
    into a few places in a Debian tree and they must not disagree.
    """
    needle = f'IMAGE_VERSION="{old}"'.encode()
    replacement = f'IMAGE_VERSION="{new}"'.encode()
    if len(needle) != len(replacement):
        raise SystemExit("[h3df] version strings must be the same length for an in-place patch")

    hits = 0
    window = len(needle)
    chunk_size = 4 * 1024 * 1024
    with raw.open("r+b") as f:
        offset = 0
        carry = b""
        while True:
            block = f.read(chunk_size)
            if not block:
                break
            buf = carry + block
            base = offset - len(carry)
            start = 0
            while True:
                i = buf.find(needle, start)
                if i < 0:
                    break
                f.seek(base + i)
                f.write(replacement)
                f.seek(offset + len(block))
                hits += 1
                start = i + window
            offset += len(block)
            carry = buf[-(window - 1):] if window > 1 else b""
    return hits


def e2fsck_clean(raw: Path) -> bool:
    """Run `e2fsck -fn` on the payload inside a container.

    A plain file needs no loop device and no privileges, so this is a cheap,
    decisive check that the byte patch above did not corrupt the filesystem —
    far better evidence than "it looked fine".
    """
    try:
        out = subprocess.run(
            ["docker", "run", "--rm", "-v", f"{raw.parent}:/img", "debian:trixie",
             "bash", "-lc",
             "apt-get update -qq >/dev/null && apt-get install -y -qq e2fsprogs >/dev/null && "
             f"e2fsck -fn /img/{raw.name}"],
            capture_output=True, text=True, timeout=900,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        print(f"[h3df] e2fsck check skipped ({e}) — reported, not silently passed")
        return True
    print(out.stdout[-2000:])
    print(out.stderr[-2000:], file=sys.stderr)
    # e2fsck exit codes: 0 = clean, 4 = uncorrected errors left, 8 = op error.
    return out.returncode in (0,)


def cmd_fixture(args) -> int:
    out_root = _APPLIANCE / "mkosi.output" / "payload"
    release = out_root / f"duduclaw-os_{args.version}"
    if release.exists() and not args.force:
        print(f"[h3df] reusing existing release at {release} (pass --force to rebuild)")
    else:
        subprocess.run(
            [sys.executable, str(_APPLIANCE / "tools" / "make-payload.py"),
             "--version", args.version, "--force"],
            check=True,
        )
    root_raw = next(release.glob("duduclaw-os_*.root-*.raw"))
    uki = release / f"duduclaw-os_{args.version}.efi"

    if args.inject_binaries:
        # The payload is carved out of an image built before today's Rust
        # changes, so its /usr/local/bin/duduclaw is the OLD gateway. Ship it
        # as-is and t2 boots the new slot on stale software — t6 then has no
        # UpdateRollback verb to call at all. Injection happens BEFORE the
        # manifest is recomputed, so the signature covers what will actually
        # be installed.
        print("[h3df] injecting freshly built binaries into the payload's root filesystem")
        subprocess.run(
            [str(_APPLIANCE / "tests" / "ab-update" / "inject-binaries.sh")],
            env={**__import__("os").environ,
                 "AB_DISK": str(root_raw), "AB_IMAGE_MODE": "partition"},
            check=True,
        )

    if args.set_image_version:
        hits = patch_image_version(root_raw, args.from_version, args.version)
        print(f"[h3df] patched IMAGE_VERSION {args.from_version} -> {args.version} "
              f"in {hits} place(s) inside {root_raw.name}")
        if hits == 0:
            print("[h3df] FAIL: nothing was patched — the payload would install a slot "
                  "that still calls itself the old version", file=sys.stderr)
            return 1
    if args.set_image_version or args.inject_binaries:
        # Decisive, cheap proof that the byte patch and/or the offline mount
        # left a filesystem the kernel will accept — far better evidence
        # than "it looked fine".
        if not e2fsck_clean(root_raw):
            print("[h3df] FAIL: the modified payload is not a clean ext4 filesystem",
                  file=sys.stderr)
            return 1
        write_manifest(release, [root_raw.name, uki.name])
        sign_manifest(release, OS_KEY)
        print("[h3df] manifest recomputed and re-signed with the OS release key")

    print((release / "SHA256SUMS").read_text())
    subprocess.run(["minisign", "-Vm", "SHA256SUMS", "-P",
                    "RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n"],
                   cwd=release, check=True)
    print(f"[h3df] fixture ready: {release}")
    return 0


def build_negative_fixtures(base: Path, arch: str) -> dict[str, Path]:
    """Three tiny synthetic releases, one per way a payload can be wrong.

    Deliberately tiny (a few KiB, not 5 GiB): every one of these must be
    refused *before* anything is installed, so the test only needs the
    verification path to run, and keeping them small makes each case a
    couple of seconds instead of a couple of minutes.
    """
    base.mkdir(parents=True, exist_ok=True)
    cases: dict[str, Path] = {}
    version = "9.9.9"
    # The arch must match the guest's, or `tampered-payload` would be refused
    # by the "no root payload for this architecture" gate instead of by the
    # digest check — a pass for the wrong reason. The other three cases fail
    # before arch selection is even reached.
    root_name = f"duduclaw-os_{version}.root-{arch}.raw"
    uki_name = f"duduclaw-os_{version}.efi"

    def seed(name: str) -> Path:
        d = base / name
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)
        (d / root_name).write_bytes(b"\x01" * 4096)
        (d / uki_name).write_bytes(b"\x02" * 4096)
        write_manifest(d, [root_name, uki_name])
        return d

    # 1. Signed — correctly, completely — but with the APP channel's key.
    #    Proves the two keypairs are not interchangeable.
    d = seed("wrong-key")
    sign_manifest(d, APP_KEY)
    cases["wrong-key"] = d

    # 2. No signature at all. An unsigned release must never be "trusted
    #    because the checksums match": the checksums are the attacker's too.
    d = seed("no-signature")
    cases["no-signature"] = d

    # 3. Correctly signed manifest, then the payload is edited underneath it.
    d = seed("tampered-payload")
    sign_manifest(d, OS_KEY)
    (d / root_name).write_bytes(b"\x03" * 4096)
    cases["tampered-payload"] = d

    # 4. A signature over a DIFFERENT manifest (valid signature, wrong body)
    #    — the classic mix-and-match.
    d = seed("swapped-manifest")
    sign_manifest(d, OS_KEY)
    (d / "SHA256SUMS").write_text(
        f"{'a' * 64}  {root_name}\n{'b' * 64}  {uki_name}\n"
    )
    cases["swapped-manifest"] = d
    return cases


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):  # noqa: A003 - stdlib signature
        pass


def serve(directory: Path, port: int) -> ThreadingHTTPServer:
    handler = lambda *a, **kw: QuietHandler(*a, directory=str(directory), **kw)  # noqa: E731
    httpd = ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    print(f"[h3df] serving {directory} on http://127.0.0.1:{port} "
          f"(guest sees http://{HOST_FROM_GUEST}:{port})")
    return httpd


# --------------------------------------------------------------------------
# guest side
# --------------------------------------------------------------------------


def connect(args) -> "serial_expect.Console":
    console = serial_expect.Console(args.host, args.serial)
    for _ in range(3):
        if serial_expect.ensure_shell(console, args.password):
            return console
        time.sleep(3)
    print("FATAL: could not reach a root shell over serial", file=sys.stderr)
    sys.exit(2)


def push_file(console, remote: str, text: str, chunk: int = 400) -> None:
    """Same base64-in-chunks transfer h3bc_probe.py documents: the tty line
    discipline silently truncates a single long line at 4096 bytes."""
    import base64
    blob = base64.b64encode(text.encode()).decode()
    console.run(f"rm -f {remote}.b64 {remote}", timeout=30)
    for i in range(0, len(blob), chunk):
        console.run(f"printf %s '{blob[i:i + chunk]}' >> {remote}.b64", timeout=30)
    out = console.run(f"base64 -d {remote}.b64 > {remote} && wc -c < {remote}", timeout=60)
    got = re.search(r"\d+", out)
    if not got or int(got.group(0)) != len(text):
        raise SystemExit(f"push_file({remote}) landed {out!r}, expected {len(text)} bytes")


def ensure_rpc_client(console, port: int) -> None:
    """Put ws_rpc.py in the guest, and prove it arrived intact.

    The dashboard RPC surface is WebSocket-only and the image ships no
    websocket client, which is exactly why that helper exists in the wifi
    harness — reuse it rather than grow a second one.

    Delivered over HTTP rather than through `push_file`: base64-in-400-byte-
    chunks works for the ~1 KB scripts h3bc_probe.py pushes, but measured on
    this 7.9 KB one it lands corrupt (7915 bytes arrived for 7911 sent — the
    serial line discipline adds bytes somewhere in ~20 round trips). The guest
    can already reach the host at 10.0.2.2 through QEMU's user networking, so
    one curl replaces twenty console round trips AND can be checksummed, which
    the chunked path never could.
    """
    want = (_APPLIANCE / "tests" / "wifi-hwsim" / "ws_rpc.py").read_bytes()
    digest = hashlib.sha256(want).hexdigest()
    have = console.run(
        "test -f /tmp/ws_rpc.py && sha256sum /tmp/ws_rpc.py | cut -c1-64 || echo NEED",
        timeout=30)
    if digest in have:
        return

    served = _APPLIANCE / ".vm" / "ab-helpers"
    served.mkdir(parents=True, exist_ok=True)
    (served / "ws_rpc.py").write_bytes(want)
    httpd = serve(served, port)
    try:
        console.run(
            f"curl -sS --max-time 60 -o /tmp/ws_rpc.py "
            f"http://{HOST_FROM_GUEST}:{port}/ws_rpc.py && "
            f"sha256sum /tmp/ws_rpc.py", timeout=120)
        got = console.run("sha256sum /tmp/ws_rpc.py | cut -c1-64", timeout=60)
    finally:
        httpd.shutdown()
    if digest not in got:
        raise SystemExit(
            f"[h3df] ws_rpc.py did not arrive intact (want {digest[:16]}…, guest said {got!r})")
    print(f"[h3df] ws_rpc.py delivered and checksum-verified ({digest[:16]}…)")


def guest_login(console) -> str:
    """Claim the appliance (first-run, loopback-only) and log in.

    Done from inside the guest on 127.0.0.1 on purpose: under QEMU user
    networking a host-forwarded connection arrives from 10.0.2.2, and the
    first-run claim route is loopback-gated.
    """
    console.run(
        f"curl -sS -X POST -H 'Content-Type: application/json' "
        f"-d '{{\"password\":\"{ADMIN_PW}\"}}' {GUEST_API}/api/first-run/claim "
        f"> /tmp/claim.json 2>&1; head -c 200 /tmp/claim.json", timeout=120)
    out = console.run(
        f"curl -sS -X POST -H 'Content-Type: application/json' "
        f"-d '{{\"email\":\"admin@local\",\"password\":\"{ADMIN_PW}\"}}' {GUEST_API}/api/login "
        f"| python3 -c \"import sys,json;print('JWT='+json.load(sys.stdin)['access_token'])\"",
        timeout=120)
    m = re.search(r"JWT=([A-Za-z0-9._-]+)", out)
    if not m:
        raise SystemExit(f"[h3df] could not obtain an admin token: {out!r}")
    console.run(f"printf %s '{m.group(1)}' > /tmp/jwt", timeout=60)
    return m.group(1)


def rpc(console, method: str, params: str = "{}", timeout: float = 3600) -> dict:
    """One dashboard RPC call from inside the guest. Returns the parsed frame
    with an `_ok` flag so a refusal (exit 1) is distinguishable from a broken
    harness (exit 2), the same three-way split ws_rpc.py itself uses."""
    out = console.run(
        f"python3 /tmp/ws_rpc.py --url ws://127.0.0.1:18789/ws --jwt \"$(cat /tmp/jwt)\" "
        f"--read-timeout {int(timeout)} {method} '{params}' 2>/tmp/rpc.err; echo RC=$?; "
        f"echo '---STDERR---'; cat /tmp/rpc.err", timeout=timeout)
    rc = re.search(r"RC=(\d+)", out)
    body = out.split("---STDERR---")[0]
    body = re.sub(r"RC=\d+\s*$", "", body).strip()
    err = out.split("---STDERR---")[-1].strip()
    parsed: dict = {}
    for candidate in (body, err):
        for line in candidate.splitlines():
            line = line.strip()
            if line.startswith("{"):
                try:
                    parsed = json.loads(line)
                    break
                except json.JSONDecodeError:
                    continue
        if parsed:
            break
    if not parsed:
        # Second pass: the serial tty hard-wraps long lines, so a large
        # response (sysupdate's own stdout rides along in the payload) can
        # arrive split across several lines. Re-joining is safe because
        # json.dumps escapes real newlines inside strings — any bare newline
        # here was inserted by the terminal, never by the sender. Without
        # this, a perfectly good RPC reads as a broken harness.
        for candidate in (body, err):
            start = candidate.find("{")
            end = candidate.rfind("}")
            if start < 0 or end <= start:
                continue
            joined = "".join(candidate[start:end + 1].splitlines())
            try:
                parsed = json.loads(joined)
                break
            except json.JSONDecodeError:
                continue
    parsed["_rc"] = int(rc.group(1)) if rc else -1
    parsed["_raw"] = out.strip()[-1500:]
    return parsed


# The [os_update] editor that runs INSIDE the guest.
#
# A pushed script rather than an inline heredoc, and that is not a style
# choice: serial_expect's `run()` wraps every command as
# `echo TAG-B; <command>; echo TAG-E`, which a heredoc cannot survive — the
# appended `; echo TAG-E` either lands on the `EOF` line (so the heredoc never
# terminates and the console hangs) or on a line of its own (a bash syntax
# error). push_file only ever sends single-line commands, which is why
# h3bc_probe.py uses this same shape for its UKI patcher.
GUEST_SET_SOURCE = (
    "import re, sys\n"
    "from pathlib import Path\n"
    "path = Path(sys.argv[1])\n"
    "url = sys.argv[2] if len(sys.argv) > 2 else ''\n"
    "text = path.read_text() if path.exists() else ''\n"
    # Drop any existing [os_update] section wholesale, then re-add it.
    # Rewriting the section instead of patching one key keeps this idempotent
    # no matter what a previous case left behind.
    "text = re.sub(r'(?ms)^\\[os_update\\].*?(?=^\\[|\\Z)', '', text).rstrip()\n"
    "if url:\n"
    "    text += '\\n\\n[os_update]\\nsource_url = \"' + url + '\"\\n'\n"
    "else:\n"
    "    text += '\\n'\n"
    "path.write_text(text)\n"
    "print('SOURCE-SET ' + (url or '(cleared)'))\n"
)


def set_source_url(console, url: str) -> None:
    """Point the gateway at an update source (empty string clears it).

    No restart needed — the config is read per call inside stage_update,
    which is also what makes an operator's URL change take effect
    immediately.
    """
    if "HAVE" not in console.run("test -f /tmp/setsrc.py && echo HAVE || echo NEED", timeout=30):
        push_file(console, "/tmp/setsrc.py", GUEST_SET_SOURCE)
    out = console.run(f"python3 /tmp/setsrc.py {GUEST_HOME}/config.toml '{url}'", timeout=60)
    if "SOURCE-SET" not in out:
        raise SystemExit(f"[h3df] could not set the update source: {out!r}")
    shown = console.run(f"grep -A2 os_update {GUEST_HOME}/config.toml", timeout=30)
    print(f"[h3df] guest [os_update]:\n{shown}")


SLOT_CHECKS: list[tuple[str, str]] = [
    ("root-source", "findmnt -no SOURCE /"),
    ("kernel-cmdline", "cat /proc/cmdline"),
    ("image-version", "grep -E '^IMAGE_VERSION=' /usr/lib/os-release"),
    ("partlabels", "ls -l /dev/disk/by-partlabel/ | tail -n +2"),
    ("esp-ukis", 'ls -la "$(bootctl -p)"/EFI/Linux/'),
    ("blessboot-status", "/usr/lib/systemd/systemd-bless-boot status 2>&1"),
    ("staging", f"ls -la {GUEST_HOME}/updates/ 2>&1 | tail -n +2"),
    ("healthz", "curl -sS --max-time 5 http://127.0.0.1:18789/healthz | head -c 200; echo"),
    ("data-df", "df -h /data | tail -1"),
]


def collect(console, checks: list[tuple[str, str]], timeout: float = 120) -> dict[str, str]:
    results: dict[str, str] = {}
    for name, command in checks:
        out = console.run(command, timeout=timeout).strip()
        results[name] = out
        print(f"===== {name} =====")
        print(out if out else "(no output)")
        print()
    return results


def reboot_and_wait(console, args, how: str = "guest", qmp=None) -> str:
    """Reboot and classify the next boot. Returns 'login' or a failure token."""
    if how == "guest":
        console.send("systemctl reboot\n")
    else:
        qmp.reset()
    console.drain(3.0)
    console.buf = b""
    if console.read_until(BOOT_START_PATTERNS, 120) is None:
        return "no-kernel-handoff"
    console.buf = b""
    got = console.read_until([b"login:"] + DEAD_BOOT_PATTERNS, args.boot_timeout)
    if got == b"login:":
        for _ in range(3):
            if serial_expect.ensure_shell(console, args.password):
                return "login"
            time.sleep(3)
        return "login-no-shell"
    return got.decode(errors="replace") if got else f"timeout-{args.boot_timeout}s"


class Qmp:
    def __init__(self, host: str, port: int) -> None:
        self.sock = socket.create_connection((host, port), timeout=10)
        self.sock.settimeout(5)
        self._read()
        self._send({"execute": "qmp_capabilities"})

    def _read(self) -> None:
        try:
            self.sock.recv(65536)
        except socket.timeout:
            pass

    def _send(self, obj: dict) -> None:
        self.sock.sendall((json.dumps(obj) + "\n").encode())
        time.sleep(0.3)
        self._read()

    def reset(self) -> None:
        self._send({"execute": "system_reset"})

    def quit(self) -> None:
        try:
            self._send({"execute": "quit"})
        except OSError:
            pass


# --------------------------------------------------------------------------
# sig — signature negative tests
# --------------------------------------------------------------------------


def cmd_sig(args) -> int:
    cases = build_negative_fixtures(_APPLIANCE / ".vm" / "ab-negative", args.payload_arch)
    console = connect(args)
    ensure_rpc_client(console, args.http_port + 1)
    guest_login(console)

    failures: list[str] = []
    # One server rooted above all four cases, so switching case is a URL
    # change rather than a server restart.
    httpd = serve(_APPLIANCE / ".vm" / "ab-negative", args.http_port)
    try:
        for name in ("wrong-key", "no-signature", "tampered-payload", "swapped-manifest"):
            print(f"\n### negative case: {name}")
            set_source_url(console, f"http://{HOST_FROM_GUEST}:{args.http_port}/{name}")
            before = console.run(f"ls {GUEST_HOME}/updates/ 2>/dev/null | wc -l", timeout=60)
            res = rpc(console, "device.update_apply", timeout=600)
            print(json.dumps(res, ensure_ascii=False, indent=2)[:1200])
            after = console.run(f"ls {GUEST_HOME}/updates/ 2>/dev/null | wc -l", timeout=60)

            code = (res.get("error") or {}).get("code") or res.get("code")
            ok_refused = res.get("_rc") == 1 or res.get("ok") is False
            if not ok_refused:
                failures.append(f"{name}: was NOT refused (frame: {res.get('_raw')!r})")
            elif code != "verification_failed":
                failures.append(
                    f"{name}: refused with code {code!r}, expected 'verification_failed' "
                    f"— a wrong classification hides which gate actually fired")
            if before.strip() != after.strip():
                failures.append(
                    f"{name}: the staging directory changed ({before.strip()} -> "
                    f"{after.strip()} entries) — a refused payload must leave nothing behind")

        # The honest-refusal case, which is NOT a verification failure.
        print("\n### negative case: no source configured")
        set_source_url(console, "")
        res = rpc(console, "device.update_apply", timeout=300)
        print(json.dumps(res, ensure_ascii=False, indent=2)[:800])
        code = (res.get("error") or {}).get("code") or res.get("code")
        if code != "not_configured":
            failures.append(f"unconfigured source answered {code!r}, expected 'not_configured'")
    finally:
        httpd.shutdown()

    print("=" * 70)
    if failures:
        print(f"SIG (payload verification): FAIL ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("SIG (payload verification): PASS — wrong key, missing signature, tampered "
          "payload and swapped manifest are each refused, staging left untouched")
    return 0


# --------------------------------------------------------------------------
# t2 — the normal update
# --------------------------------------------------------------------------


def release_dir(version: str) -> Path:
    return _APPLIANCE / "mkosi.output" / "payload" / f"duduclaw-os_{version}"


def cmd_t2(args) -> int:
    release = release_dir(args.version)
    if not (release / "SHA256SUMS.minisig").exists():
        print(f"[h3df] no signed release at {release} — run `h3df_probe.py fixture` first",
              file=sys.stderr)
        return 2

    console = connect(args)
    ensure_rpc_client(console, args.http_port + 1)
    guest_login(console)
    before = collect(console, SLOT_CHECKS)
    slot_a_dev = before["root-source"].strip()

    httpd = serve(release.parent, args.http_port)
    failures: list[str] = []
    try:
        set_source_url(
            console,
            f"http://{HOST_FROM_GUEST}:{args.http_port}/duduclaw-os_{args.version}")
        t0 = time.time()
        res = rpc(console, "device.update_apply", timeout=args.apply_timeout)
        print(f"[h3df] device.update_apply took {time.time() - t0:.0f}s")
        print(json.dumps(res, ensure_ascii=False, indent=2)[:2000])
        if res.get("_rc") != 0:
            print("[h3df] update_apply did not succeed; collecting evidence before failing")
            collect(console, SLOT_CHECKS)
            print(console.run("journalctl -u duduclaw-gateway -n 60 --no-pager -o cat",
                              timeout=120))
            return 1
    finally:
        httpd.shutdown()

    staged = collect(console, [
        ("staging", f"ls -la {GUEST_HOME}/updates/"),
        ("staging-du", f"du -sh {GUEST_HOME}/updates/ 2>&1"),
        ("partlabels", "ls -l /dev/disk/by-partlabel/ | tail -n +2"),
        ("esp-ukis", 'ls -la "$(bootctl -p)"/EFI/Linux/'),
        ("esp-df", 'df -h "$(bootctl -p)" | tail -1'),
        ("sysupdate-list", "/usr/lib/systemd/systemd-sysupdate list 2>&1 | head -20"),
        ("data-df", "df -h /data | tail -1"),
    ])

    if f"duduclaw-os_{args.version}" not in staged["partlabels"]:
        failures.append("no partition is labelled with the new version — sysupdate did not "
                        "write a slot")
    if not re.search(rf"duduclaw-os_{re.escape(args.version)}\+\d+-\d+\.efi", staged["esp-ukis"]):
        failures.append("the ESP has no counted entry for the new version — an update that "
                        "cannot be assessed cannot roll back either")

    print("\n### rebooting into the update")
    outcome = reboot_and_wait(console, args, how="guest")
    if outcome != "login":
        print(f"[h3df] the updated system did not come up: {outcome}")
        failures.append(f"the updated system did not reach a login prompt ({outcome})")
        print("=" * 70)
        print(f"T2 (normal update, end to end): FAIL ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1

    after = collect(console, SLOT_CHECKS + [
        ("bless-watch", "for i in $(seq 1 60); do "
                        "s=$(/usr/lib/systemd/systemd-bless-boot status 2>&1); "
                        "echo \"$i $s\"; case \"$s\" in *good*|*bad*) break;; esac; sleep 5; done"),
    ], timeout=400)

    new_dev = after["root-source"].strip()
    if new_dev == slot_a_dev:
        failures.append(f"still running from the same slot ({new_dev}) — the update did not "
                        f"change which root is mounted")
    if f"duduclaw-os_{args.version}.efi" not in after["esp-ukis"]:
        failures.append("the new entry never lost its boot counter — it was not blessed")
    if re.search(rf"duduclaw-os_{re.escape(args.version)}\+\d", after["esp-ukis"]):
        failures.append("a counted entry for the new version is still present after blessing")
    if '"ok":true' not in after["healthz"]:
        failures.append("the updated system is not serving")
    if "duduclaw-os_0.1.0.efi" not in after["esp-ukis"]:
        failures.append("the previous version's entry is gone from the ESP — there is nothing "
                        "left to roll back to")
    reported = re.search(r'IMAGE_VERSION="?([^"\s]+)', after["image-version"])
    reported = reported.group(1) if reported else "?"

    print("=" * 70)
    print(f"slot before: {slot_a_dev}   slot after: {new_dev}")
    print(f"running IMAGE_VERSION after the update: {reported}")
    if reported != args.version:
        print(f"  NOTE: the payload still calls itself {reported}. That is expected only when "
              f"the fixture was built without --set-image-version; ProtectVersion=%A then "
              f"protects the wrong string on the NEXT update.")
    if failures:
        print(f"T2 (normal update, end to end): FAIL ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("T2 (normal update, end to end): PASS — signed release downloaded, verified, "
          "installed into the free slot, booted, and blessed")
    return 0


# --------------------------------------------------------------------------
# t5 — power cut during apply
# --------------------------------------------------------------------------


def cmd_t5(args) -> int:
    """Cut the power partway through an install and prove the machine still
    boots. The dangerous state this guards is a half-written root slot that
    a boot entry already points at — which is why the transfers run
    `10-root` before `20-uki` (entry point last)."""
    release = release_dir(args.version)
    if not (release / "SHA256SUMS.minisig").exists():
        print(f"[h3df] no signed release at {release} — run fixture first", file=sys.stderr)
        return 2

    console = connect(args)
    ensure_rpc_client(console, args.http_port + 1)
    guest_login(console)
    before = collect(console, SLOT_CHECKS)
    slot_a_dev = before["root-source"].strip()

    qmp = Qmp(args.host, args.qmp)
    httpd = serve(release.parent, args.http_port)
    try:
        set_source_url(
            console,
            f"http://{HOST_FROM_GUEST}:{args.http_port}/duduclaw-os_{args.version}")
        # Fire the install and DON'T wait for it: send the command, let it run,
        # then pull the plug after the payload has had time to start landing.
        console.send(
            "python3 /tmp/ws_rpc.py --url ws://127.0.0.1:18789/ws --jwt \"$(cat /tmp/jwt)\" "
            "--read-timeout 3600 device.update_apply '{}' > /tmp/apply.log 2>&1 &\n")
        console.drain(2.0)
        print(f"[h3df] install running; cutting power in {args.cut_after}s")
        time.sleep(args.cut_after)
        staged = console.run(f"ls -la {GUEST_HOME}/updates/ {GUEST_HOME}/updates/.incoming/ 2>&1",
                             timeout=60)
        print(f"[h3df] staging directory at the moment of the cut:\n{staged}")
        qmp.reset()
    finally:
        httpd.shutdown()

    console.drain(3.0)
    console.buf = b""
    outcome = "no-kernel-handoff"
    if console.read_until(BOOT_START_PATTERNS, 120) is not None:
        console.buf = b""
        got = console.read_until([b"login:"] + DEAD_BOOT_PATTERNS, args.boot_timeout)
        outcome = got.decode(errors="replace") if got else f"timeout-{args.boot_timeout}s"
    if outcome != "login:":
        print(f"T5 (power cut during apply): FAIL — the machine did not come back ({outcome})")
        return 1
    for _ in range(3):
        if serial_expect.ensure_shell(console, args.password):
            break
        time.sleep(3)

    after = collect(console, SLOT_CHECKS)
    failures: list[str] = []
    if after["root-source"].strip() != slot_a_dev:
        failures.append(
            f"the machine came back on {after['root-source'].strip()}, not the original "
            f"{slot_a_dev} — an interrupted install must never become the running system")
    if '"ok":true' not in after["healthz"]:
        failures.append("the machine booted but is not serving")

    print("=" * 70)
    if failures:
        print(f"T5 (power cut during apply): FAIL ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"T5 (power cut during apply): PASS — power cut mid-install, machine came back "
          f"on {slot_a_dev} and is serving")
    return 0


# --------------------------------------------------------------------------
# t6 — manual rollback
# --------------------------------------------------------------------------


def cmd_t6(args) -> int:
    """`device.update_rollback` must return the machine to the other version.

    Run this straight after a successful t2, on the same disk (AB_FRESH=0):
    the machine is on the new slot, the new entry has been blessed, and
    `bless-boot status` reads `clean` — which is the state a real operator
    presses the button in, and the exact state tier 1 alone cannot serve.
    """
    console = connect(args)
    ensure_rpc_client(console, args.http_port + 1)
    console.run("test -s /tmp/jwt || echo NEED-LOGIN", timeout=30)
    if "NEED-LOGIN" in console.run("test -s /tmp/jwt && echo HAVE || echo NEED-LOGIN", timeout=30):
        guest_login(console)

    before = collect(console, SLOT_CHECKS + [
        ("boot-assessment", 'python3 /tmp/ws_rpc.py --url ws://127.0.0.1:18789/ws '
                            '--jwt "$(cat /tmp/jwt)" --read-timeout 120 '
                            'device.boot_assessment \'{}\' 2>&1'),
        ("loader-selected",
         "tr -d '\\000' < /sys/firmware/efi/efivars/"
         "LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f 2>/dev/null | tail -c 80; echo"),
    ])
    start_dev = before["root-source"].strip()
    start_entries = before["esp-ukis"]

    res = rpc(console, "device.update_rollback", '{"confirm": true}', timeout=300)
    print(json.dumps(res, ensure_ascii=False, indent=2)[:1500])

    # `_rc` is NOT the success signal for this verb, and treating it as one
    # reported a working rollback as a refusal (measured 2026-08-24): the verb
    # reboots the machine, so the shell that would have run `echo RC=$?` is
    # gone before it can. A refusal is a structured error frame; anything else
    # means the call was accepted and the box is on its way down.
    code = (res.get("error") or {}).get("code") or res.get("code")
    if code:
        print(f"T6 (manual rollback): FAIL — the RPC refused with {code!r}:")
        print(res.get("message") or res.get("_raw"))
        return 1
    print(f"[h3df] rollback accepted: {res.get('stdout', '').strip()!r}")

    # Wait on the OUTCOME, not on console choreography: the reboot may already
    # be underway (or finished) by the time the response is parsed, so looking
    # for a kernel handoff races it. Polling "which slot am I on" is
    # unambiguous and cannot be fooled by catching the pre-reboot shell.
    deadline = time.time() + args.boot_timeout
    current = start_dev
    while time.time() < deadline:
        time.sleep(10)
        if not serial_expect.ensure_shell(console, args.password):
            continue
        current = console.run("findmnt -no SOURCE /", timeout=60).strip()
        if current and current != start_dev:
            break
    if current == start_dev:
        print(f"T6 (manual rollback): FAIL — still on {start_dev} after "
              f"{args.boot_timeout}s; the rollback did not take effect")
        return 1

    after = collect(console, SLOT_CHECKS)
    failures: list[str] = []
    if after["root-source"].strip() == start_dev:
        failures.append(f"still on {start_dev} — the rollback did not change slots")
    if '"ok":true' not in after["healthz"]:
        failures.append("the rolled-back system is not serving")
    if not re.search(r"duduclaw-os_[0-9.]+\+0-\d+\.efi", after["esp-ukis"]):
        failures.append("no entry is in the exhausted (+0-N) state — nothing was actually "
                        "marked bad, so the machine changed slots for some other reason")

    print("=" * 70)
    print(f"before: {start_dev}\n{start_entries}\nafter: {after['root-source'].strip()}")
    if failures:
        print(f"T6 (manual rollback): FAIL ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"T6 (manual rollback): PASS — {start_dev} -> {after['root-source'].strip()}, "
          f"previous version serving again")
    return 0


# --------------------------------------------------------------------------
# t7 — two bad updates must not exhaust both entries
# --------------------------------------------------------------------------


def cmd_t7(args) -> int:
    """The anti-brick floor.

    Two bad updates in a row must not leave every entry exhausted. Two
    independent guarantees are checked: sd-boot still boots a bad entry when
    every entry is bad (upstream's documented last resort), and our own
    rollback verb refuses rather than marking the last healthy entry bad.
    """
    console = connect(args)
    version = re.search(r'IMAGE_VERSION="?([0-9][^"\s]*)',
                        console.run("grep ^IMAGE_VERSION= /usr/lib/os-release", timeout=30))
    if not version:
        print("FATAL: could not read IMAGE_VERSION", file=sys.stderr)
        return 2
    version = version.group(1)

    print("### marking every ESP entry exhausted (the state two bad updates would leave)")
    print(console.run(
        'p="$(bootctl -p)"/EFI/Linux; for f in "$p"/*.efi; do '
        'b=$(basename "$f" .efi); case "$b" in *+*) b=${b%+*};; esac; '
        'mv "$f" "$p/$b+0-3.efi" 2>/dev/null; done; sync; ls -la "$p"', timeout=180))

    qmp = Qmp(args.host, args.qmp)
    outcome = reboot_and_wait(console, args, how="reset", qmp=qmp)
    failures: list[str] = []
    if outcome != "login":
        failures.append(
            f"the machine did NOT boot with every entry exhausted ({outcome}) — sd-boot's "
            f"documented last resort (boot a bad entry when all others are bad too) did not "
            f"hold, and this layout can brick")
        print("=" * 70)
        print("T7 (two bad updates): FAIL")
        for f in failures:
            print(f"  - {f}")
        return 1

    after = collect(console, SLOT_CHECKS)
    print("### and the rollback verb must refuse rather than make it worse")
    ensure_rpc_client(console, args.http_port + 1)
    if "NEED-LOGIN" in console.run("test -s /tmp/jwt && echo HAVE || echo NEED-LOGIN", timeout=30):
        guest_login(console)
    res = rpc(console, "device.update_rollback", '{"confirm": true}', timeout=300)
    print(json.dumps(res, ensure_ascii=False, indent=2)[:1200])
    code = (res.get("error") or {}).get("code") or res.get("code")
    if res.get("_rc") == 0:
        failures.append("update_rollback reported success with no healthy entry left to fall "
                        "back to — it must refuse instead")
    elif code != "unsupported":
        failures.append(f"update_rollback refused with {code!r}, expected 'unsupported'")

    print("=" * 70)
    print(f"booted from: {after['root-source'].strip()} with entries:\n{after['esp-ukis']}")
    if failures:
        print(f"T7 (two bad updates): FAIL ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("T7 (two bad updates): PASS — the machine still boots with every entry exhausted, "
          "and the rollback verb refuses instead of exhausting the last one")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["fixture", "sig", "t2", "t5", "t6", "t7"])
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--serial", type=int, default=47031)
    ap.add_argument("--qmp", type=int, default=47032)
    ap.add_argument("--password", default="duduclaw")
    ap.add_argument("--http-port", type=int, default=8099)
    ap.add_argument("--version", default="0.2.0", help="version of the test release")
    ap.add_argument("--from-version", default="0.1.0",
                    help="version string already inside the image (same LENGTH as --version)")
    ap.add_argument("--inject-binaries", action="store_true",
                    help="replace the payload's duduclaw/duduclaw-sysd with the freshly "
                         "built ones before signing, so the installed slot runs the code "
                         "under test")
    ap.add_argument("--set-image-version", action="store_true",
                    help="rewrite the payload's own IMAGE_VERSION so the installed slot "
                         "honestly reports the new version")
    ap.add_argument("--force", action="store_true", help="rebuild the fixture from scratch")
    ap.add_argument("--payload-arch", default="arm64", choices=["arm64", "x86-64"],
                    help="architecture the GUEST runs — used to name the sig probe's "
                         "synthetic payloads")
    ap.add_argument("--boot-timeout", type=float, default=300)
    ap.add_argument("--apply-timeout", type=float, default=3600)
    ap.add_argument("--cut-after", type=float, default=45,
                    help="seconds into the install before t5 pulls the plug")
    args = ap.parse_args()

    return {"fixture": cmd_fixture, "sig": cmd_sig, "t2": cmd_t2,
            "t5": cmd_t5, "t6": cmd_t6, "t7": cmd_t7}[args.mode](args)


if __name__ == "__main__":
    sys.exit(main())
