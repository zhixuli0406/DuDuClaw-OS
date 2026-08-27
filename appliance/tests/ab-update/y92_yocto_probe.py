#!/usr/bin/env python3
"""Y9-2 (2026-08-27) — Yocto-line A/B update QEMU probe: T2 + T6.

Trimmed port of h3df_probe.py (the Debian/mkosi line's H3d/H3f acceptance
probe) onto the Yocto line's `duduclaw-image-ab` recipe (Y8-1). Only the
two cases the Y9-2 ticket asks for (T2 normal update, T6 manual rollback)
are ported — sig/t5/t7/t8r are NOT here, this is an honest subset, not a
claim that the other cases were run.

What is reused **verbatim in spirit** from h3df_probe.py, because it is
genuinely distro-agnostic (same systemd tools, same gateway RPC surface —
the crate is vendored byte-identical onto this line per the Y8-1 handoff
notes):
  - connect/collect/reboot_and_wait/Qmp
  - SLOT_CHECKS shell probes (findmnt/bootctl/systemd-bless-boot/curl/df)
  - ws_rpc.py itself (same file, appliance/tests/wifi-hwsim/ws_rpc.py) —
    but NOT h3df_probe.py's guest-side delivery mechanism, see below.

What is DIFFERENT on this line (see each constant's own comment below):
  - x86_64 not arm64 (payload-arch, MatchPattern's `%a` = "x86-64")
  - DUDUCLAW_AB_DATA_SIZE_MB defaults to 1024M in the wks (vs. Debian's
    grown-to-order /data) — NOT auto-grown at boot on this line yet (Y8-1
    known gap: the GrowFileSystem bit is set but no repart.d/ consumes it).
    A too-small /data means a full root payload cannot stage. See --data-mb
    on the `fixture`/`prepare-disk` flow this script's caller must arrange
    BEFORE this script runs (this script does not resize the wic itself —
    that is `duduclaw-ab-partflags.bbclass`'s DUDUCLAW_AB_DATA_SIZE_MB, a
    build-time override, applied by re-running `bitbake duduclaw-image-ab`
    with a bumped value in local.conf, not something a test probe can do to
    an already-built image after the fact).
  - release directory lives under appliance/.vm/ab-yocto-payload/ (Yocto has
    no mkosi.output/), not appliance/mkosi.output/payload/.
  - **RPC layer runs on the HOST, not the guest** (Y9-2 correction,
    2026-08-27): h3df_probe.py pushes ws_rpc.py onto the guest and runs it
    there via guest python3 — that assumes an on-device python3
    interpreter, which the Debian/mkosi line's appliance image has and
    this Yocto line's images (duduclaw-image/-minimal/-ab.bb) do NOT
    (`grep -rn python3 meta-duduclaw/recipes-core/images/*.bb` is empty;
    confirmed live by an actual guest shell: "-sh: python3: command not
    found"). guest_login()/rpc() below run ws_rpc.py and the login HTTP
    calls on the HOST against `boot-ab-yocto.sh`'s forwarded dashboard
    port (`AB_DASH_PORT`/`--dash-port`, default 18797) instead — ws_rpc.py
    is a pure-stdlib WebSocket client with no on-device dependency, so it
    works identically from either side of the QEMU NAT. set_source_url()
    similarly uses BusyBox awk instead of a pushed python3 script (awk
    confirmed present on this image; python3 is the one on-device
    scripting gap this ticket found).

The VM is expected to be running already
(appliance/tests/ab-update/boot-ab-yocto.sh).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import socket
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

_APPLIANCE = Path(__file__).resolve().parent.parent.parent
_REPO = _APPLIANCE.parent

HOST_FROM_GUEST = "10.0.2.2"
GUEST_HOME = "/data/duduclaw"
ADMIN_PW = "duduclaw-ab-test-pw"
OS_KEY = Path.home() / ".minisign" / "duduclaw-os-release.key"
PAYLOAD_ROOT = _APPLIANCE / ".vm" / "ab-yocto-payload"


def _load(name: str):
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

# `EFI stub: Booting Linux Kernel` / `Booting Linux on physical CPU` — kept
# for the historical record only (see reboot_and_wait's own comment):
# neither string ever appears on this line's console output at all, on any
# boot, so this is NOT read by anything anymore.
BOOT_START_PATTERNS = [b"EFI stub: Booting Linux Kernel", b"Booting Linux on physical CPU"]
DEAD_BOOT_PATTERNS = [
    b"You are in emergency mode",
    b"Entering emergency mode",
    # NOT "Timed out waiting for device" (Y9-2, 2026-08-27): this line's
    # /etc/fstab has a genuine, independently-tracked bug (/data mounts via
    # a hardcoded /dev/sda4, which does not exist on virtio-blk — confirmed
    # present on EVERY boot, cold or warm, slot A or B; see this ticket's
    # own TODO write-up) that prints exactly this string for ~90s on every
    # single boot before the machine continues anyway. Treating it as fatal
    # here would make reboot_and_wait report a false FAIL on every
    # otherwise-successful boot — read_until scans a trailing byte window
    # for ANY listed substring, so one transient (and already-diagnosed,
    # non-blocking) generator timeout would look identical to a real
    # boot-halting one. `Cannot open root device` below stays: THAT
    # specifically means the root filesystem itself never mounted, which
    # is the actual "this boot is dead" signal T3-style fault injection
    # would produce.
    b"Cannot open root device",
    b"Kernel panic",
]


# --------------------------------------------------------------------------
# host side: fixture
# --------------------------------------------------------------------------


def release_dir(version: str) -> Path:
    return PAYLOAD_ROOT / f"duduclaw-os_{version}"


def cmd_fixture(args) -> int:
    """Build a signed test release straight from the Yocto .wic build output.

    Unlike h3df_probe.py's cmd_fixture, --raw/--uki are REQUIRED here (no
    mkosi.output/ convention to default to) — the caller must point at the
    actual deploy artifact paths for this build (see this ticket's own
    handoff notes for exactly where they landed).
    """
    release = release_dir(args.version)
    if release.exists() and not args.force:
        print(f"[y92] reusing existing release at {release} (pass --force to rebuild)")
    else:
        cmd = [
            sys.executable, str(_APPLIANCE / "tools" / "make-payload.py"),
            "--raw", str(args.raw), "--uki", str(args.uki),
            "--image-version", args.image_version,
            "--version", args.version,
            "--outdir", str(PAYLOAD_ROOT),
            "--sign-key", str(OS_KEY),
            "--force",
        ]
        print(f"[y92] {' '.join(cmd)}")
        subprocess.run(cmd, check=True)

    root_raw = next(release.glob("duduclaw-os_*.root-*.raw"))
    uki = release / f"duduclaw-os_{args.version}.efi"
    print(f"[y92] payload root:  {root_raw} ({root_raw.stat().st_size} bytes)")
    print(f"[y92] payload uki:   {uki} ({uki.stat().st_size} bytes)")
    subprocess.run(["minisign", "-Vm", "SHA256SUMS", "-P",
                    "RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n"],
                   cwd=release, check=True)
    print(f"[y92] fixture ready: {release}")
    return 0


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):  # noqa: A003
        pass


def serve(directory: Path, port: int) -> ThreadingHTTPServer:
    handler = lambda *a, **kw: QuietHandler(*a, directory=str(directory), **kw)  # noqa: E731
    httpd = ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    print(f"[y92] serving {directory} on http://127.0.0.1:{port} "
          f"(guest sees http://{HOST_FROM_GUEST}:{port})")
    return httpd


# --------------------------------------------------------------------------
# guest side (verbatim logic from h3df_probe.py — distro-agnostic)
# --------------------------------------------------------------------------


def connect(args) -> "serial_expect.Console":
    console = serial_expect.Console(args.host, args.serial)
    for _ in range(3):
        if serial_expect.ensure_shell(console, args.password):
            return console
        time.sleep(3)
    print("FATAL: could not reach a root shell over serial", file=sys.stderr)
    sys.exit(2)


# --------------------------------------------------------------------------
# host side: RPC layer (Y9-2 correction, 2026-08-27)
# --------------------------------------------------------------------------
#
# h3df_probe.py's approach — push ws_rpc.py onto the GUEST and run it there
# via guest python3 — assumes the appliance image ships a python3
# interpreter. It does on the Debian/mkosi line. It does NOT on this Yocto
# line: `grep -rn python3 meta-duduclaw/recipes-core/images/*.bb` is empty
# for duduclaw-image(-minimal|-ab).bb, confirmed live by an actual boot
# ("-sh: python3: command not found" from a guest shell during this
# ticket). Rather than adding a python3 interpreter to the shipped image
# just to satisfy a test harness (the gateway itself is a self-contained
# Rust binary + systemd and needs no on-device scripting language at all),
# this probe runs the SAME ws_rpc.py **on the host** against the VM's
# already-forwarded dashboard port (`boot-ab-yocto.sh`'s
# `-netdev ... hostfwd=tcp:127.0.0.1:${DASH_PORT}-:18789`) — ws_rpc.py's
# own design goal ("pure stdlib, no mount, no loop device, no root" is
# make-payload.py's phrasing but the same spirit applies) means it does not
# care which side of the NAT it runs on, only that it can reach the
# gateway's `/ws` endpoint. Guest-side interaction stays limited to what
# BusyBox/coreutils-lite already provides (SLOT_CHECKS, set_source_url
# below) — confirmed present on this image by direct probing during this
# ticket: awk, sed, curl, base64, bootctl, systemd-bless-boot (absolute
# path, not on PATH). NOT present: python3 (the main gap this correction
# addresses), `findmnt` (BusyBox applet not enabled — SLOT_CHECKS'
# ROOT_SOURCE_CMD reads /proc/mounts instead), `head -c` (BusyBox's head
# lacks -c entirely — `cut -c` used instead).
def guest_login(console, args) -> str:
    import urllib.request

    # `/api/first-run/claim` refuses anything not genuinely loopback
    # (found live during this ticket: calling it from the HOST through
    # boot-ab-yocto.sh's hostfwd NAT gets `403 first-run setup is only
    # available from localhost` — SLIRP's NAT means the gateway sees the
    # connection arrive from its own internal address, not 127.0.0.1, and
    # correctly refuses it; this is the gateway doing its job, not a bug).
    # So claim MUST run from inside the guest, over its own real loopback
    # — plain curl, no python3, no JSON parsing needed (a bare `"ok":true`
    # substring check is enough, matching h3df_probe.py's own
    # fire-and-forget tolerance of an already-claimed system on a re-run
    # against the same disk).
    claimed = console.run(
        "curl -sS -X POST -H 'Content-Type: application/json' "
        f"-d '{{\"password\":\"{ADMIN_PW}\"}}' http://127.0.0.1:18789/api/first-run/claim",
        timeout=30)
    print(f"[y92] first-run claim (guest-side): {claimed!r}")

    # `/api/login` has no such restriction (confirmed live: succeeds from
    # the host through the same hostfwd port once claim has set the
    # password) — stays on the host so the response can be JSON-parsed
    # with the standard library instead of guest-side string surgery.
    base = f"http://127.0.0.1:{args.dash_port}"
    login_body = json.dumps({"email": "admin@local", "password": ADMIN_PW}).encode()
    req = urllib.request.Request(
        f"{base}/api/login", data=login_body,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        parsed = json.loads(resp.read())
    token = parsed.get("access_token")
    if not token:
        raise SystemExit(f"[y92] could not obtain an admin token: {parsed!r}")
    return token


def rpc(console, args, method: str, params: str = "{}", timeout: float = 3600) -> dict:
    jwt = getattr(rpc, "_jwt", None) or guest_login(console, args)
    rpc._jwt = jwt  # cache for the process lifetime — one login per probe run
    cmd = [
        sys.executable, str(_APPLIANCE / "tests" / "wifi-hwsim" / "ws_rpc.py"),
        "--url", f"ws://127.0.0.1:{args.dash_port}/ws", "--jwt", jwt,
        "--read-timeout", str(int(timeout)), method, params,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 30)
    parsed: dict = {}
    for candidate in (proc.stdout, proc.stderr):
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
    parsed["_rc"] = proc.returncode
    parsed["_raw"] = (proc.stdout + "\n---STDERR---\n" + proc.stderr).strip()[-1500:]
    return parsed


# Guest-side config.toml [os_update] rewrite via awk, NOT python3 (see the
# host-side RPC layer's own comment above — this image has no python3 at
# all; BusyBox awk was confirmed present by direct probing during this
# ticket). Strips any existing `[os_update]` section (from its header line
# up to, but not including, the next `[section]` header or EOF) then
# appends a fresh one — same net effect as h3df_probe.py's python regex,
# expressed in an awk state machine instead.
def set_source_url(console, url: str) -> None:
    strip_cmd = (
        "awk 'BEGIN{skip=0} "
        "/^\\[os_update\\]/{skip=1; next} "
        "/^\\[/{skip=0} "
        "skip{next} "
        "{print}' "
        f"{GUEST_HOME}/config.toml > {GUEST_HOME}/config.toml.new "
        f"&& mv {GUEST_HOME}/config.toml.new {GUEST_HOME}/config.toml"
    )
    console.run(strip_cmd, timeout=30)
    if url:
        append_cmd = (
            f"printf '\\n[os_update]\\nsource_url = \"%s\"\\n' '{url}' "
            f">> {GUEST_HOME}/config.toml && echo SOURCE-SET"
        )
    else:
        append_cmd = f"printf '\\n' >> {GUEST_HOME}/config.toml && echo SOURCE-SET"
    out = console.run(append_cmd, timeout=30)
    if "SOURCE-SET" not in out:
        raise SystemExit(f"[y92] could not set the update source: {out!r}")
    shown = console.run(f"grep -A2 os_update {GUEST_HOME}/config.toml", timeout=30)
    print(f"[y92] guest [os_update]:\n{shown}")


# BusyBox on this image has no `findmnt` applet at all (confirmed live:
# `which findmnt` → empty) — h3df_probe.py's original command silently
# returns nothing here instead of erroring, which would have made every
# T2/T6 slot-identity assertion compare "" == "" and pass for the wrong
# reason. /proc/mounts + `readlink -f` gets the same canonical
# `/dev/vdaN` DESIGN-ab-update-rollback-2026-08.md §6.4 calls for
# ("用分割區號碼...不要用 PARTLABEL"), using only tools confirmed present
# (awk, xargs, readlink — all BusyBox applets on this image).
ROOT_SOURCE_CMD = "awk '$2 == \"/\" {print $1; exit}' /proc/mounts | xargs readlink -f"

SLOT_CHECKS: list[tuple[str, str]] = [
    ("root-source", ROOT_SOURCE_CMD),
    ("kernel-cmdline", "cat /proc/cmdline"),
    # No `IMAGE_VERSION=` key exists in this line's /usr/lib/os-release at
    # all (confirmed live) — os-update.rs's `ProtectVersion=%A` reads that
    # exact specifier and 10-duduclaw-root.transfer's own comment already
    # flags a DIFFERENT, adjacent mismatch (DISTRO_VERSION carries a
    # "-y1-bringup" suffix the wks's bare-version partition name lacks);
    # this ticket found the key is missing outright, a distinct fact worth
    # recording separately. `VERSION_ID=` is the field this os-release
    # actually ships and is where this evidence check is redirected —
    # ONLY as this probe's own reporting field, NOT a claim that it fixes
    # os_update.rs's specifier resolution.
    ("image-version", "grep -E '^VERSION_ID=' /usr/lib/os-release"),
    ("partlabels", "ls -l /dev/disk/by-partlabel/ | tail -n +2"),
    ("esp-ukis", 'ls -la "$(bootctl -p)"/EFI/Linux/'),
    ("blessboot-status", "/usr/lib/systemd/systemd-bless-boot status 2>&1"),
    ("staging", f"ls -la {GUEST_HOME}/updates/ 2>&1 | tail -n +2"),
    # `head -c` is not built into this BusyBox (confirmed live: "head:
    # invalid option -- 'c'" then a busybox usage dump swallowing curl's
    # piped body, which also broke curl with "Failed writing body"); `cut
    # -c1-200` is the BusyBox-confirmed equivalent.
    ("healthz", "curl -sS --max-time 5 http://127.0.0.1:18789/healthz | cut -c1-200; echo"),
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
    # Y9-2 correction (2026-08-27), SECOND pass: the ORIGINAL h3df_probe.py-
    # derived two-stage design (wait for a BOOT_START_PATTERNS "kernel
    # handoff" line, THEN wait for login) does not work on this line at
    # all. First suspicion was a drain-then-clear race (fixed above, kept
    # for the record) — but a raw, unfiltered 25-second capture of an
    # actual `systemctl reboot` on this kernel/UKI proved neither
    # `EFI stub: Booting Linux Kernel` nor `Booting Linux on physical CPU`
    # appears ANYWHERE in the serial stream, drain race or not (this
    # line's console output style, or `systemd.show_status=auto` quiet-boot
    # behavior, simply never prints either string — a wrong-marker bug, not
    # a timing bug). Meanwhile the actual boot outcome was independently
    # confirmed correct by manual reconnect every single time this
    # "failed" (`root-source` on the new slot, `bootctl status` showing the
    # new entry, `systemd-bless-boot status: good`) — so BOOT_START_PATTERNS
    # was actively producing false FAILs on a mechanism that works.
    # Collapsed to the single check that actually matters for T2/T6's own
    # acceptance criteria (DESIGN-ab-update-rollback-2026-08.md §6.2: "開進
    # B 槽、健康" — slot + health, never "did dmesg print a specific kernel
    # message"): wait for `login:`/`#` (or a DEAD_BOOT_PATTERNS failure
    # signature) across the full `args.boot_timeout` budget from the
    # moment reboot is issued. A machine that is genuinely hung produces
    # NEITHER signal and still correctly times out; a machine that boots
    # (fast or slow, with or without a visible kernel-handoff banner)
    # reaches one of them.
    if how == "guest":
        console.send("systemctl reboot\n")
    else:
        qmp.reset()
    console.drain(3.0)
    got = console.read_until([b"login:", b"#"] + DEAD_BOOT_PATTERNS, args.boot_timeout)
    if got in (b"login:", b"#"):
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
# t2 — normal update, end to end
# --------------------------------------------------------------------------


def cmd_t2(args) -> int:
    release = release_dir(args.version)
    if not (release / "SHA256SUMS.minisig").exists():
        print(f"[y92] no signed release at {release} — run `y92_yocto_probe.py fixture` first",
              file=sys.stderr)
        return 2

    console = connect(args)
    guest_login(console, args)
    before = collect(console, SLOT_CHECKS)
    slot_a_dev = before["root-source"].strip()

    httpd = serve(release.parent, args.http_port)
    failures: list[str] = []
    try:
        set_source_url(
            console,
            f"http://{HOST_FROM_GUEST}:{args.http_port}/duduclaw-os_{args.version}")
        t0 = time.time()
        res = rpc(console, args, "device.update_apply", timeout=args.apply_timeout)
        print(f"[y92] device.update_apply took {time.time() - t0:.0f}s")
        print(json.dumps(res, ensure_ascii=False, indent=2)[:2000])
        if res.get("_rc") != 0:
            print("[y92] update_apply did not succeed; collecting evidence before failing")
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
        print(f"[y92] the updated system did not come up: {outcome}")
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

    print("=" * 70)
    print(f"slot before: {slot_a_dev}   slot after: {new_dev}")
    if failures:
        print(f"T2 (normal update, end to end): FAIL ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("T2 (normal update, end to end): PASS — signed release downloaded, verified, "
          "installed into the free slot, booted, and blessed")
    return 0


# --------------------------------------------------------------------------
# t6 — manual rollback
# --------------------------------------------------------------------------


def cmd_t6(args) -> int:
    console = connect(args)
    guest_login(console, args)

    before = collect(console, SLOT_CHECKS)
    boot_assessment_before = rpc(console, args, "device.boot_assessment", "{}", timeout=120)
    print("[y92] boot-assessment (before):",
          json.dumps(boot_assessment_before, ensure_ascii=False)[:500])
    start_dev = before["root-source"].strip()
    start_entries = before["esp-ukis"]

    res = rpc(console, args, "device.update_rollback", '{"confirm": true}', timeout=300)
    print(json.dumps(res, ensure_ascii=False, indent=2)[:1500])

    code = (res.get("error") or {}).get("code") or res.get("code")
    if code:
        print(f"T6 (manual rollback): FAIL — the RPC refused with {code!r}:")
        print(res.get("message") or res.get("_raw"))
        return 1
    print(f"[y92] rollback accepted: {res.get('stdout', '').strip()!r}")

    deadline = time.time() + args.boot_timeout
    current = start_dev
    while time.time() < deadline:
        time.sleep(10)
        if not serial_expect.ensure_shell(console, args.password):
            continue
        current = console.run(ROOT_SOURCE_CMD, timeout=60).strip()
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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["fixture", "t2", "t6"])
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--serial", type=int, default=47051)
    ap.add_argument("--qmp", type=int, default=47052)
    ap.add_argument("--dash-port", type=int, default=18797,
                    help="host port forwarded to the guest's gateway dashboard "
                         "(boot-ab-yocto.sh's AB_DASH_PORT, hostfwd=...-:18789) "
                         "— the RPC layer runs on the HOST against this port, "
                         "not inside the guest (see guest_login/rpc's own "
                         "comment: this image has no python3 to run ws_rpc.py "
                         "with)")
    ap.add_argument("--password", default="duduclaw")  # unused: serial-autologin-root+empty-root-password
    ap.add_argument("--http-port", type=int, default=8199)
    ap.add_argument("--version", default="1.62.1", help="version of the test release")
    ap.add_argument("--image-version", default="1.62.0",
                    help="DUDUCLAW_PLATFORM_VERSION of the source .wic (fixture only)")
    ap.add_argument("--raw", type=Path, help="path to the built .wic (fixture only)")
    ap.add_argument("--uki", type=Path, help="path to the standalone UKI .efi (fixture only)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--boot-timeout", type=float, default=600,
                    help="TCG (no HVF, cross-arch) boots much slower than the aarch64/hvf "
                         "Debian-line VM — default raised accordingly")
    ap.add_argument("--apply-timeout", type=float, default=3600)
    args = ap.parse_args()

    if args.mode == "fixture" and (not args.raw or not args.uki):
        ap.error("fixture requires --raw and --uki")

    return {"fixture": cmd_fixture, "t2": cmd_t2, "t6": cmd_t6}[args.mode](args)


if __name__ == "__main__":
    sys.exit(main())
