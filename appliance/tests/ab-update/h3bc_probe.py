#!/usr/bin/env python3
"""H3b/H3c acceptance probe — boot counting + health gate + automatic rollback.

Extends h3a_probe.py's shape (report everything, then assert, so a failure
shows evidence instead of a verdict) to the two packages that actually arm the
A/B machinery:

  H3b  sd-boot boot counting on the factory UKI (APPLIANCE_BOOT_COUNTING=3,
       the shipping default since 2026-08-23).
  H3c  duduclaw-health-check.service gating boot-complete.target, so a boot is
       blessed only when the gateway really serves and duduclaw-sysd is
       reachable.

Subcommands map to the design's test matrix
(commercial/docs/DESIGN-ab-update-rollback-2026-08.md §6.2):

  t0      First boot of a fresh disk: counting is genuinely in effect
          (NOT `clean`), the health gate ran and passed, bless-boot cleared
          the counter. **This is the anchor for everything else** — if
          counting silently no-ops, T3 "passes" without ever having counted
          anything, which is the worst possible false positive.
  t1      N healthy reboots in a row must NOT drift into a rollback — the
          regression test for "counting armed with nothing clearing it".
  esp     ESP capacity measurement, including a real three-UKI peak (T9).
  inject  Stage a deliberately unbootable "update" into the ESP: a copy of the
          running UKI whose baked root=PARTUUID= points at a partition that
          cannot exist and whose IMAGE_VERSION is bumped so sd-boot prefers
          it. This is the T3 fault injection.
  t3      Drive the whole rollback: reset until the box comes back, then prove
          it came back on slot A *and* that the bad entry was really attempted
          the configured number of times.
  t4      The gate must be able to say NO: a box that boots but does not
          serve keeps its counter and is not blessed. T0 only proves it can
          say yes.
  slot    One-shot "where am I" report (root device, version, ESP entries).

Usage:
  h3bc_probe.py t0     [--host H] [--serial 47031] [--password duduclaw]
  h3bc_probe.py t1     [...] [--reboots 3]
  h3bc_probe.py esp    [...]
  h3bc_probe.py inject [...] [--bad-version 0.2.0]
  h3bc_probe.py t3     [...] [--qmp 47032] [--tries 3]
  h3bc_probe.py t4     [...]
  h3bc_probe.py slot   [...]
"""

from __future__ import annotations

import argparse
import base64
import importlib.util
import json
import re
import socket
import sys
import time
from pathlib import Path

_APPLIANCE = Path(__file__).resolve().parent.parent.parent


def _load(name: str):
    """Load one of the host-local VM helpers from appliance/.vm/inject/.

    That directory is gitignored (it also holds multi-hundred-MB binaries), so
    resolve at runtime and say plainly what is missing rather than dying on an
    ImportError. Same approach as h3a_probe.py — duplicating these helpers
    would mean two drifting copies of the code every VM round depends on.
    """
    path = _APPLIANCE / ".vm" / "inject" / f"{name}.py"
    if not path.exists():
        print(f"missing {path} — host-local helper (appliance/.vm is gitignored); "
              f"copy it from another checkout or VM round", file=sys.stderr)
        sys.exit(2)
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:  # pragma: no cover - environment guard
        print(f"cannot load {path}", file=sys.stderr)
        sys.exit(2)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


serial_expect = _load("serial_expect")

# The EFI variable sd-boot sets when it has renamed a counted boot entry. Its
# presence is the ONLY unambiguous proof that boot counting is in effect this
# boot: systemd-bless-boot's generator keys off exactly this, and without it
# `bless-boot status` answers `clean` — which is indistinguishable, from the
# outside, from "we never armed counting at all".
BOOT_COUNT_VAR = "LoaderBootCountPath-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"

# Deliberately impossible root. A PARTUUID of all zeroes is never assigned by
# repart/mkosi, so the initrd waits for a device that will never appear and the
# boot dies in the initrd — the "boot-time death" fault depth of design §6.3.
DEAD_PARTUUID = "00000000-0000-0000-0000-000000000000"


# --------------------------------------------------------------------------
# guest-side helpers
# --------------------------------------------------------------------------


def connect(host: str, port: int, password: str) -> "serial_expect.Console":
    console = serial_expect.Console(host, port)
    for _ in range(3):
        if serial_expect.ensure_shell(console, password):
            return console
        time.sleep(3)
    print("FATAL: could not reach a root shell over serial", file=sys.stderr)
    sys.exit(2)


def collect(console, checks: list[tuple[str, str]], timeout: float = 60) -> dict[str, str]:
    results: dict[str, str] = {}
    for name, command in checks:
        out = console.run(command, timeout=timeout).strip()
        results[name] = out
        print(f"===== {name} =====")
        print(out if out else "(no output)")
        print()
    return results


def push_file(console, remote: str, text: str, chunk: int = 400) -> None:
    """Write a host-side string into a guest file over the serial console.

    base64 in fixed-size chunks: the tty line discipline has a canonical-mode
    input limit (4096 bytes on Linux) and a single long line is silently
    truncated, which would produce a corrupt script and a baffling failure.
    """
    blob = base64.b64encode(text.encode()).decode()
    console.run(f"rm -f {remote}.b64 {remote}", timeout=30)
    for i in range(0, len(blob), chunk):
        console.run(f"printf %s '{blob[i:i + chunk]}' >> {remote}.b64", timeout=30)
    out = console.run(f"base64 -d {remote}.b64 > {remote} && wc -c < {remote}", timeout=60)
    got = re.search(r"\d+", out)
    if not got or int(got.group(0)) != len(text):
        raise SystemExit(f"push_file({remote}) landed {out!r}, expected {len(text)} bytes")


# The UKI patcher that runs INSIDE the guest. Kept tiny and dependency-free
# (python3 is in the image's Packages=). It rewrites two fixed-width spans in
# place, so no PE offset, section size or header changes — the same reasoning
# appliance/tools/uki-slots.py documents for its slot-B derivation.
GUEST_PATCHER = r'''
import struct, sys

src, dst, newver = sys.argv[1], sys.argv[2], sys.argv[3]
data = bytearray(open(src, "rb").read())
pe = struct.unpack_from("<I", data, 0x3C)[0]
assert data[pe:pe + 4] == b"PE\0\0", "not a PE image"
nsec = struct.unpack_from("<H", data, pe + 6)[0]
optsz = struct.unpack_from("<H", data, pe + 20)[0]
table = pe + 24 + optsz
sec = {}
for i in range(nsec):
    e = table + i * 40
    name = data[e:e + 8].rstrip(b"\0").decode("ascii", "replace")
    raw_size, raw_ptr = struct.unpack_from("<II", data, e + 16)
    sec[name] = (raw_ptr, raw_size)

off, size = sec[".cmdline"]
cmd = bytes(data[off:off + size])
i = cmd.find(b"root=PARTUUID=")
assert i >= 0, "UKI has no root=PARTUUID= to break"
old_root = cmd[i + 14:i + 50].decode()
dead = b"%s"
assert len(dead) == 36
data[off + i + 14:off + i + 50] = dead

off, size = sec[".osrel"]
osr = bytes(data[off:off + size])
j = osr.find(b"IMAGE_VERSION=")
assert j >= 0, ".osrel has no IMAGE_VERSION"
val = osr[j + 14:osr.find(b"\n", j)].strip().strip(b'"')
assert len(val) == len(newver.encode()), "version length must match (in-place rewrite)"
p = osr.find(val, j)
data[off + p:off + p + len(val)] = newver.encode()

open(dst, "wb").write(bytes(data))

# Re-read the artifact instead of trusting the write.
check = open(dst, "rb").read()
co, cs = sec[".cmdline"]
oo, os_ = sec[".osrel"]
assert dead in check[co:co + cs], "cmdline patch did not land"
assert (b"IMAGE_VERSION=" + newver.encode()) in check[oo:oo + os_].replace(b'"', b""), \
    "osrel patch did not land"
print("PATCH-OK old_root=%%s old_version=%%s bytes=%%d" %% (old_root, val.decode(), len(check)))
''' % DEAD_PARTUUID


def esp_stats(console) -> dict[str, int]:
    """1K-block df numbers for the ESP, parsed rather than eyeballed."""
    out = console.run('df -k "$(bootctl -p)" | tail -1', timeout=30)
    fields = out.split()
    # filesystem 1K-blocks used available use% mounted
    try:
        return {"blocks": int(fields[1]), "used": int(fields[2]), "avail": int(fields[3])}
    except (IndexError, ValueError):
        raise SystemExit(f"could not parse df output: {out!r}")


def mib(kb: int) -> str:
    return f"{kb / 1024:.1f}MiB"


# --------------------------------------------------------------------------
# t0
# --------------------------------------------------------------------------

T0_CHECKS: list[tuple[str, str]] = [
    ("boot-target", "systemctl is-system-running || true"),
    ("root-source", "findmnt -no SOURCE /"),
    ("image-version", "grep -E '^IMAGE_(ID|VERSION)=' /usr/lib/os-release"),
    ("tries-file", "cat /etc/kernel/tries 2>/dev/null || echo NO-TRIES-FILE"),
    ("esp-path", "bootctl -p 2>/dev/null || echo NONE"),
    ("esp-ukis", 'ls -la "$(bootctl -p)"/EFI/Linux/'),
    # The decisive evidence for "counting is really in effect". efivarfs files
    # carry a 4-byte attribute prefix and UTF-16 content; the tr/strings dance
    # is just to make the path readable.
    ("bootcount-var",
     f"test -e /sys/firmware/efi/efivars/{BOOT_COUNT_VAR} && "
     f"(tr -d '\\000' < /sys/firmware/efi/efivars/{BOOT_COUNT_VAR} | tail -c 120; echo) "
     f"|| echo NO-BOOTCOUNT-VAR"),
    ("blessboot-status", "/usr/lib/systemd/systemd-bless-boot status 2>&1"),
    ("blessboot-unit", "systemctl is-active systemd-bless-boot.service 2>&1 || true"),
    ("blessboot-pull",
     "systemctl show systemd-bless-boot.service -p Requires -p After -p WantedBy -p RequiredBy 2>&1"),
    ("blessboot-generator", "ls -l /run/systemd/generator*/*/systemd-bless-boot.service 2>&1 | head -5"),
    ("boot-complete", "systemctl is-active boot-complete.target 2>&1 || true"),
    ("boot-complete-deps",
     "systemctl show boot-complete.target -p Requires -p RequiredBy -p WantedBy 2>&1"),
    ("health-unit",
     "systemctl show duduclaw-health-check.service -p ActiveState -p Result -p ExecMainStatus 2>&1"),
    ("health-journal",
     "journalctl -b -u duduclaw-health-check.service --no-pager -o cat 2>&1 | tail -12"),
    ("healthz", "curl -sS --max-time 5 http://127.0.0.1:18789/healthz | head -c 300; echo"),
    ("sysd-socket", "ls -l /run/duduclaw/sysd.sock 2>&1"),
    ("failed-units", "systemctl list-units --state=failed --no-legend --no-pager || true"),
    ("boot-time", "systemd-analyze 2>&1 | head -2"),
    ("esp-df", 'df -h "$(bootctl -p)" | tail -1'),
]


def watch_bless(console, budget: float) -> list[tuple[float, str]]:
    """Poll bless-boot status until it settles on good/bad, recording every
    distinct state seen. Logging in over serial happens long before the
    gateway is up, so on a healthy first boot this normally captures the real
    `indeterminate` -> `good` transition rather than only the end state."""
    seen: list[tuple[float, str]] = []
    start = time.time()
    while time.time() - start < budget:
        raw = console.run("/usr/lib/systemd/systemd-bless-boot status 2>&1", timeout=30)
        words = set(re.findall(r"[a-z]+", raw.lower()))
        state = next((s for s in ("good", "bad", "indeterminate", "clean") if s in words), "?")
        if not seen or seen[-1][1] != state:
            seen.append((round(time.time() - start, 1), state))
            print(f"[bless-watch] +{seen[-1][0]}s -> {state}")
        if state in ("good", "bad"):
            break
        time.sleep(2)
    return seen


def cmd_t0(args) -> int:
    console = connect(args.host, args.serial, args.password)

    print("### watching systemd-bless-boot state from the earliest reachable shell")
    transitions = watch_bless(console, args.bless_budget)
    print()

    results = collect(console, T0_CHECKS)
    version = re.search(r"IMAGE_VERSION=\"?([0-9][^\"\s]*)", results["image-version"])
    version = version.group(1) if version else "?"

    failures: list[str] = []

    def require(name: str, ok: bool, why: str) -> None:
        if not ok:
            failures.append(f"{name}: {why}\n      got: {results.get(name, '')!r}")

    require("boot-target",
            "running" in results["boot-target"] or "degraded" in results["boot-target"],
            "system never finished booting")

    # ---- H3b: counting is genuinely armed -------------------------------
    require("tries-file", results["tries-file"].strip() == "3",
            "/etc/kernel/tries is not 3 — the factory UKI was not built with "
            "APPLIANCE_BOOT_COUNTING=3, so nothing is being counted")
    require("bootcount-var", "NO-BOOTCOUNT-VAR" not in results["bootcount-var"],
            "sd-boot did not set LoaderBootCountPath: this boot was NOT counted. "
            "Everything downstream (bless, rollback) is a no-op, and any later "
            "rollback test would pass for the wrong reason")
    require("bootcount-var", "duduclaw-os_" in results["bootcount-var"],
            "LoaderBootCountPath does not name a duduclaw UKI")
    require("bootcount-var", re.search(r"\+\d", results["bootcount-var"]) is not None,
            "the counted path carries no +N-M suffix, so no counter was in flight")

    states = [s for _t, s in transitions]
    require("blessboot-status", "clean" not in states,
            "systemd-bless-boot reported `clean` while a counter was in flight — "
            "boot counting is silently doing nothing (§2.2 trap 2: an unwritable "
            "ESP produces exactly this, and a bad image would then retry forever)")
    require("blessboot-status", bool(states) and states[-1] == "good",
            f"boot never reached the `good` state within {args.bless_budget}s "
            f"(observed {transitions}) — nothing cleared the counter, so this "
            f"machine will roll itself back after 3 boots")

    # ---- H3c: the gate is what granted the blessing ----------------------
    require("health-unit", "ActiveState=active" in results["health-unit"],
            "duduclaw-health-check.service is not active — the gate did not run, "
            "so the blessing (if any) was granted without checking anything")
    require("health-unit", "Result=success" in results["health-unit"],
            "the health gate did not succeed")
    require("boot-complete", results["boot-complete"].strip() == "active",
            "boot-complete.target was not reached")
    require("blessboot-unit", results["blessboot-unit"].strip() in ("active", "activating"),
            "systemd-bless-boot.service did not run")
    require("healthz", '"ok":true' in results["healthz"],
            "the gateway's /healthz is not reporting ok:true")

    # ---- the blessing actually renamed the entry -------------------------
    require("esp-ukis", f"duduclaw-os_{version}.efi" in results["esp-ukis"],
            f"the ESP has no counter-free duduclaw-os_{version}.efi — blessing "
            f"should have stripped the +N-M suffix from the filename")
    require("esp-ukis",
            re.search(rf"duduclaw-os_{re.escape(version)}\+\d", results["esp-ukis"]) is None,
            "a counted (+N-M) UKI name is still present after blessing")

    require("failed-units", "duduclaw" not in results["failed-units"],
            "a duduclaw unit is in the failed state")

    print("=" * 70)
    print(f"bless-boot transitions observed: {transitions}")
    if failures:
        print(f"T0 (boot counting + health gate): FAIL ({len(failures)} assertion(s))")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("T0 (boot counting + health gate): PASS")
    saw_indeterminate = "indeterminate" in states
    print(f"  observed `indeterminate` before blessing: "
          f"{'yes' if saw_indeterminate else 'no (login landed after the gate had already passed)'}")
    return 0


# --------------------------------------------------------------------------
# esp / inject
# --------------------------------------------------------------------------


def cmd_esp(args) -> int:
    """T9 data: measure the real ESP peak with three UKIs present."""
    console = connect(args.host, args.serial, args.password)
    base = esp_stats(console)
    listing = console.run('ls -la "$(bootctl -p)"/EFI/Linux/', timeout=30)
    print(listing)
    uki = console.run('ls "$(bootctl -p)"/EFI/Linux/*.efi | head -1', timeout=30).strip()
    size_out = console.run(f'stat -c %s "{uki}"', timeout=30).strip()
    uki_kb = int(re.search(r"\d+", size_out).group(0)) // 1024

    print(f"[esp] total={mib(base['blocks'])} used={mib(base['used'])} "
          f"avail={mib(base['avail'])} uki={mib(uki_kb)}")

    peaks = {"1-uki": base}
    ok_two = ok_three = False
    for n, name in ((2, "probe2"), (3, "probe3")):
        r = console.run(
            f'cp "{uki}" "$(bootctl -p)"/EFI/Linux/.esp-{name}.efi && sync && echo COPY-OK || echo COPY-FAIL',
            timeout=300)
        got = "COPY-OK" in r
        peaks[f"{n}-uki"] = esp_stats(console)
        print(f"[esp] {n} UKIs present: {'fits' if got else 'DID NOT FIT'} "
              f"used={mib(peaks[f'{n}-uki']['used'])} avail={mib(peaks[f'{n}-uki']['avail'])}")
        if n == 2:
            ok_two = got
        else:
            ok_three = got
    console.run('rm -f "$(bootctl -p)"/EFI/Linux/.esp-probe2.efi '
                '"$(bootctl -p)"/EFI/Linux/.esp-probe3.efi && sync', timeout=120)
    after = esp_stats(console)
    print(f"[esp] cleaned up: used={mib(after['used'])} avail={mib(after['avail'])}")

    print(json.dumps({k: {kk: mib(vv) for kk, vv in v.items()} for k, v in peaks.items()}, indent=2))
    if not (ok_two and ok_three):
        print("ESP CAPACITY: FAIL — three concurrent UKIs do not fit; an update "
              "would write a partial entry point, the worst possible state")
        return 1
    headroom = peaks["3-uki"]["avail"]
    print(f"ESP CAPACITY: PASS — three UKIs fit, {mib(headroom)} still free at peak")
    return 0


def cmd_inject(args) -> int:
    console = connect(args.host, args.serial, args.password)
    before = esp_stats(console)
    uki = console.run('ls "$(bootctl -p)"/EFI/Linux/duduclaw-os_*.efi | head -1', timeout=30).strip()
    if not uki.endswith(".efi"):
        print(f"FATAL: no UKI found in the ESP ({uki!r})", file=sys.stderr)
        return 2
    bad = f"$(bootctl -p)/EFI/Linux/duduclaw-os_{args.bad_version}+{args.tries}-0.efi"
    print(f"[inject] source UKI: {uki}")
    print(f"[inject] fake update: duduclaw-os_{args.bad_version}+{args.tries}-0.efi "
          f"(root=PARTUUID={DEAD_PARTUUID})")

    push_file(console, "/tmp/mkbad.py", GUEST_PATCHER)
    out = console.run(f'python3 /tmp/mkbad.py "{uki}" "{bad}" {args.bad_version} 2>&1', timeout=600)
    print(out)
    if "PATCH-OK" not in out:
        print("FATAL: the bad UKI was not produced", file=sys.stderr)
        return 1
    console.run("sync", timeout=120)
    print(console.run('ls -la "$(bootctl -p)"/EFI/Linux/', timeout=30))
    after = esp_stats(console)
    print(f"[inject] ESP used {mib(before['used'])} -> {mib(after['used'])} "
          f"(avail {mib(after['avail'])})")
    return 0


# --------------------------------------------------------------------------
# slot / t3
# --------------------------------------------------------------------------

SLOT_CHECKS: list[tuple[str, str]] = [
    ("root-source", "findmnt -no SOURCE /"),
    ("kernel-cmdline", "cat /proc/cmdline"),
    ("image-version", "grep -E '^IMAGE_VERSION=' /usr/lib/os-release"),
    ("esp-ukis", 'ls -la "$(bootctl -p)"/EFI/Linux/'),
    ("blessboot-status", "/usr/lib/systemd/systemd-bless-boot status 2>&1"),
    ("healthz", "curl -sS --max-time 5 http://127.0.0.1:18789/healthz | head -c 200; echo"),
]


def cmd_slot(args) -> int:
    console = connect(args.host, args.serial, args.password)
    collect(console, SLOT_CHECKS)
    return 0


def cmd_t1(args) -> int:
    """T1: repeated healthy reboots must NOT accumulate into a rollback.

    This is the direct regression test for the failure mode that made the H3
    package order non-negotiable — boot counting with nothing to clear the
    counter retires a perfectly good machine on the third reboot. After the
    first boot is blessed the entry carries no counter at all, so each further
    reboot must come back on the same slot with `clean` status and a
    counter-free filename.
    """
    console = serial_expect.Console(args.host, args.serial)
    failures: list[str] = []
    for round_no in range(1, args.reboots + 1):
        for _ in range(3):
            if serial_expect.ensure_shell(console, args.password):
                break
            time.sleep(3)
        else:
            print(f"T1: FAIL — no shell before reboot {round_no}")
            return 1
        print(f"\n### reboot {round_no}/{args.reboots}")
        console.send("systemctl reboot\n")
        console.drain(3.0)
        console.buf = b""
        if console.read_until(BOOT_START_PATTERNS, 90) is None:
            failures.append(f"reboot {round_no}: no kernel handoff within 90s")
            break
        if console.read_until([b"login:"], args.boot_timeout) is None:
            failures.append(f"reboot {round_no}: never reached a login prompt")
            break
        for _ in range(3):
            if serial_expect.ensure_shell(console, args.password):
                break
            time.sleep(3)
        results = collect(console, [
            ("root-source", "findmnt -no SOURCE /"),
            ("esp-ukis", 'ls "$(bootctl -p)"/EFI/Linux/'),
            ("blessboot-status", "/usr/lib/systemd/systemd-bless-boot status 2>&1"),
        ])
        if not results["root-source"].strip().endswith("vda2"):
            failures.append(f"reboot {round_no}: root moved off slot A ({results['root-source']!r})")
        if re.search(r"duduclaw-os_[0-9.]+\+\d", results["esp-ukis"]):
            failures.append(f"reboot {round_no}: a boot counter reappeared in the ESP "
                            f"({results['esp-ukis']!r}) — a healthy machine is counting down")
        if "clean" not in results["blessboot-status"]:
            failures.append(f"reboot {round_no}: bless-boot says {results['blessboot-status']!r}, "
                            f"expected `clean` (a blessed entry carries no counter)")

    print("=" * 70)
    if failures:
        print(f"T1 ({args.reboots} healthy reboots): FAIL")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"T1 ({args.reboots} healthy reboots): PASS — no counter ever came back, "
          f"root stayed on slot A")
    return 0


def cmd_t4(args) -> int:
    """T4: the health gate must have teeth — a box that boots but does not
    SERVE must not be blessed.

    T0 only proves the gate can say yes. This proves it can say no, which is
    the half that actually protects a rollback: "reached multi-user.target"
    is exactly the criterion the upstream boot-assessment path would have
    accepted, and it is not enough.

    Method: re-arm the counter on the installed entry (rename it back to
    `+<tries>`), make the gateway unable to start (mask it), reboot once. The
    machine still boots — only the *blessing* must be withheld: the counter
    survives as `+N-M`, bless-boot never runs, and `bless-boot status` reads
    `indeterminate`. Everything is restored before returning.
    """
    console = connect(args.host, args.serial, args.password)
    version = re.search(r"IMAGE_VERSION=\"?([0-9][^\"\s]*)",
                        console.run("grep ^IMAGE_VERSION= /usr/lib/os-release", timeout=30))
    if not version:
        print("FATAL: could not read IMAGE_VERSION", file=sys.stderr)
        return 2
    version = version.group(1)
    clean = f"duduclaw-os_{version}.efi"
    armed = f"duduclaw-os_{version}+{args.tries}.efi"

    print(f"### re-arming the counter: {clean} -> {armed}, and breaking the gateway")
    print(console.run(f'p="$(bootctl -p)"/EFI/Linux && mv "$p/{clean}" "$p/{armed}" && '
                      f'sync && ls "$p"', timeout=120))
    # A drop-in, not `systemctl mask`: this image ships the unit as a real
    # file in /etc/systemd/system, and mask cannot put its /dev/null symlink
    # where a regular file already lives ("File ... already exists" — measured,
    # and the first version of this test silently injected no fault at all
    # because of it). Replacing ExecStart with /bin/false makes the service
    # fail to start for real, which is the fault T4 is about.
    print(console.run(
        'mkdir -p /etc/systemd/system/duduclaw-gateway.service.d && '
        'printf "[Service]\\nExecStart=\\nExecStart=/bin/false\\n" '
        '> /etc/systemd/system/duduclaw-gateway.service.d/99-t4-break.conf && '
        'systemctl daemon-reload && echo FAULT-INJECTED', timeout=60))
    console.send("systemctl reboot\n")
    console.drain(3.0)
    console.buf = b""
    if console.read_until(BOOT_START_PATTERNS, 90) is None:
        print("T4: FAIL — the machine did not restart")
        return 1
    if console.read_until([b"login:"], args.boot_timeout) is None:
        print("T4: FAIL — the machine never reached a login prompt; T4 expects a box "
              "that BOOTS but does not serve, so this is a different failure")
        return 1
    for _ in range(3):
        if serial_expect.ensure_shell(console, args.password):
            break
        time.sleep(3)

    results = collect(console, [
        ("blessboot-status", "/usr/lib/systemd/systemd-bless-boot status 2>&1"),
        ("esp-ukis", 'ls "$(bootctl -p)"/EFI/Linux/'),
        ("health-unit", "systemctl show duduclaw-health-check.service "
                        "-p ActiveState -p Result 2>&1"),
        ("boot-complete", "systemctl is-active boot-complete.target 2>&1 || true"),
        ("blessboot-unit", "systemctl is-active systemd-bless-boot.service 2>&1 || true"),
        ("gateway", "systemctl is-active duduclaw-gateway.service 2>&1 || true"),
    ])

    failures: list[str] = []
    if results["gateway"].strip() == "active":
        failures.append("the gateway is still active — the fault was not injected")
    if "indeterminate" not in results["blessboot-status"]:
        failures.append(f"bless-boot says {results['blessboot-status']!r}; expected "
                        f"`indeterminate` (counted, and deliberately not blessed)")
    if not re.search(rf"duduclaw-os_{re.escape(version)}\+\d+-\d+\.efi", results["esp-ukis"]):
        failures.append(f"the ESP entry lost its counter ({results['esp-ukis']!r}) — "
                        f"something blessed this boot even though nothing served")
    if results["blessboot-unit"].strip() == "active":
        failures.append("systemd-bless-boot ran despite the gate not passing")
    if results["boot-complete"].strip() == "active":
        failures.append("boot-complete.target was reached with a failed gate")

    print("### restoring: remove the drop-in, restart the gateway, clear the counter")
    print(console.run(
        'rm -rf /etc/systemd/system/duduclaw-gateway.service.d && systemctl daemon-reload && '
        'systemctl reset-failed duduclaw-gateway.service 2>/dev/null; '
        'systemctl start duduclaw-gateway.service; systemctl is-active duduclaw-gateway.service',
        timeout=120))
    print(console.run(f'p="$(bootctl -p)"/EFI/Linux && '
                      f'f=$(ls "$p"/duduclaw-os_{version}+*.efi 2>/dev/null | head -1) && '
                      f'[ -n "$f" ] && mv "$f" "$p/{clean}" && sync; ls "$p"', timeout=120))

    print("=" * 70)
    if failures:
        print(f"T4 (health gate withholds the blessing): FAIL ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("T4 (health gate withholds the blessing): PASS — boot succeeded, service "
          "did not, blessing withheld, counter still ticking")
    return 0


class Qmp:
    """Just enough QMP to reset a VM. (appliance/.vm/inject/qmp.py is a CLI,
    not an importable session — resets here need a persistent connection.)"""

    def __init__(self, host: str, port: int) -> None:
        self.sock = socket.create_connection((host, port), timeout=10)
        self.sock.settimeout(5)
        self._read()                       # greeting
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


# Serial text that proves a NEW boot has started. Everything before this is
# leftover output from the previous boot still sitting in the socket, and
# classifying on it is how the first version of this probe "detected" three
# failures that had not happened yet.
BOOT_START_PATTERNS = [b"EFI stub: Booting Linux Kernel", b"Booting Linux on physical CPU"]

# Serial patterns that mean "this boot is not going to make it". Every one is
# a full phrase systemd/the kernel only ever prints when it has actually given
# up — deliberately NOT the bare word "Emergency", which appears in the unit
# description "systemd-bsod.service - Display Boot-Time Emergency Messages" on
# every healthy boot (the project's own convention 2: no unanchored substring
# tests for decisions).
DEAD_BOOT_PATTERNS = [
    b"You are in emergency mode",
    b"Entering emergency mode",
    b"Timed out waiting for device",
    b"Cannot open root device",
    b"Kernel panic",
]


def cmd_t3(args) -> int:
    """Bad update -> N failed attempts -> automatic rollback to the good entry."""
    qmp = Qmp(args.host, args.qmp)
    console = serial_expect.Console(args.host, args.serial)
    log: list[str] = []
    attempts = 0
    booted = False

    Path(args.artifacts).mkdir(parents=True, exist_ok=True)
    for round_no in range(1, args.tries + 3):
        if round_no == 1 and args.first_reboot == "guest":
            # The realistic path for the first transition: the update is
            # staged and the box reboots itself. Later rounds cannot use it —
            # by then the guest has no shell to run it in.
            print("\n### boot 1: `systemctl reboot` from inside the guest")
            for _ in range(3):
                if serial_expect.ensure_shell(console, args.password):
                    break
                time.sleep(3)
            console.send("systemctl reboot\n")
        else:
            print(f"\n### boot {round_no}: QMP system_reset")
            qmp.reset()
        # Drop whatever the previous boot was still emitting, then refuse to
        # classify anything until this boot has demonstrably started.
        console.drain(3.0)
        console.buf = b""
        started = console.read_until(BOOT_START_PATTERNS, 90)
        if started is None:
            print(f"[t3] boot {round_no}: never reached the kernel handoff within 90s")
            log.append(f"boot{round_no}=no-kernel-handoff")
            (Path(args.artifacts) / f"t3-boot{round_no}.log").write_text(
                console.buf.decode(errors="replace"))
            attempts += 1
            continue
        console.buf = b""
        got = console.read_until([b"login:"] + DEAD_BOOT_PATTERNS, args.boot_timeout)
        tail = console.buf.decode(errors="replace")
        # systemd escapes '-' as '\x2d' in device unit names, so compare with
        # separators removed rather than hoping for one spelling.
        saw_dead_root = DEAD_PARTUUID.replace("-", "") in \
            tail.replace("\\x2d", "").replace("-", "")
        (Path(args.artifacts) / f"t3-boot{round_no}.log").write_text(tail)
        if got == b"login:":
            print(f"[t3] boot {round_no}: reached a login prompt")
            log.append(f"boot{round_no}=login")
            booted = True
            break
        state = got.decode(errors="replace") if got else f"timeout after {args.boot_timeout}s"
        attempts += 1
        print(f"[t3] boot {round_no}: FAILED as designed ({state}); "
              f"dead-PARTUUID seen on console: {saw_dead_root}")
        log.append(f"boot{round_no}=failed({state})")

    if not booted:
        print(f"T3 (bad update -> automatic rollback): FAIL — the machine never "
              f"came back after {attempts} failed boots. Log: {log}")
        return 1

    for _ in range(3):
        if serial_expect.ensure_shell(console, args.password):
            break
        time.sleep(3)
    else:
        print("T3: FAIL — a login prompt appeared but the shell never opened")
        return 1

    results = collect(console, SLOT_CHECKS)
    failures: list[str] = []

    def require(name: str, ok: bool, why: str) -> None:
        if not ok:
            failures.append(f"{name}: {why}\n      got: {results.get(name, '')!r}")

    require("root-source", results["root-source"].strip().endswith("vda2"),
            "the recovered boot is not on slot A (/dev/vda2)")
    require("kernel-cmdline", DEAD_PARTUUID not in results["kernel-cmdline"],
            "the recovered boot is still using the broken cmdline")
    require("image-version", "0.1.0" in results["image-version"],
            "the recovered boot is not the factory version")
    exhausted = re.search(rf"duduclaw-os_{re.escape(args.bad_version)}\+0-(\d+)\.efi",
                          results["esp-ukis"])
    require("esp-ukis", exhausted is not None,
            f"the bad entry is not in the exhausted (+0-N) state — sd-boot did "
            f"not count it down, so the rollback did not happen for the reason "
            f"under test")
    if exhausted:
        require("esp-ukis", int(exhausted.group(1)) == args.tries,
                f"the bad entry recorded {exhausted.group(1)} attempts, expected {args.tries}")
    require("healthz", '"ok":true' in results["healthz"],
            "the rolled-back system is not serving")
    require("esp-ukis", "duduclaw-os_0.1.0.efi" in results["esp-ukis"],
            "the good entry is gone from the ESP")

    print("=" * 70)
    print(f"boot log: {log}")
    print(f"failed attempts before rollback: {attempts} (expected {args.tries})")
    if attempts != args.tries:
        failures.append(f"attempts: the bad entry was tried {attempts} times, expected {args.tries}")
    if failures:
        print(f"T3 (bad update -> automatic rollback): FAIL ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("T3 (bad update -> automatic rollback): PASS")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["t0", "t1", "t3", "t4", "esp", "inject", "slot"])
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--serial", type=int, default=47031)
    ap.add_argument("--qmp", type=int, default=47032)
    ap.add_argument("--password", default="duduclaw")
    ap.add_argument("--tries", type=int, default=3,
                    help="TriesLeft the image was built with (APPLIANCE_BOOT_COUNTING)")
    ap.add_argument("--bad-version", default="0.2.0",
                    help="version string for the injected bad update; must be the "
                         "same LENGTH as the installed version (in-place rewrite)")
    ap.add_argument("--bless-budget", type=float, default=300,
                    help="seconds to wait for bless-boot to settle in t0")
    ap.add_argument("--boot-timeout", type=float, default=200,
                    help="seconds to wait for each t3 boot to reach a login prompt")
    ap.add_argument("--first-reboot", choices=["guest", "reset"], default="guest",
                    help="how t3 leaves the healthy boot: `guest` runs "
                         "`systemctl reboot` (the realistic post-update path), "
                         "`reset` uses QMP (the hard-power-cycle path). Later "
                         "rounds always use QMP — there is no shell by then.")
    ap.add_argument("--reboots", type=int, default=3,
                    help="how many healthy reboots t1 performs")
    ap.add_argument("--artifacts", default=str(_APPLIANCE / ".vm" / "ab-artifacts"))
    args = ap.parse_args()

    return {"t0": cmd_t0, "t1": cmd_t1, "t3": cmd_t3, "t4": cmd_t4,
            "esp": cmd_esp, "inject": cmd_inject, "slot": cmd_slot}[args.mode](args)


if __name__ == "__main__":
    sys.exit(main())
