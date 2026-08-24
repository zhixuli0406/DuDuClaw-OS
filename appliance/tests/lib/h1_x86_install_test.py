#!/usr/bin/env python3
"""H1-ISO: x86-64 self-install acceptance test (2026-08-24, H1 line first bake).

Exercises the FULL install lifecycle documented in `appliance/README.md`
("The same image is both the installer and the shipped product") end to
end, under `qemu-system-x86_64` TCG (full software emulation — there is no
cross-arch accelerator on an Apple Silicon host, so this is expected to be
slow; see this repo's own README note on the x86-64 shipping build path).

There is no separate "installer" build to test — the golden
`duduclaw-os.raw` IS the installer
(`mkosi.extra/usr/local/sbin/duduclaw-usb-install.sh`, wired via
`duduclaw-usb-install.service`, `Before=duduclaw-gateway.service`): booted
from removable media with exactly one internal NVMe present, it dd's its
own boot disk onto that NVMe and powers off. This script reproduces that
exact topology in QEMU rather than building any new install tooling:

  Phase A (install):
    - `usb-boot.raw`  = a copy of the golden image, attached via
      `usb-storage` on a `qemu-xhci` controller — this is what makes the
      guest kernel see it as REMOVABLE (`/sys/block/*/removable == 1`,
      the exact check `duduclaw-usb-install.sh` step 1 makes).
    - `nvme-target.raw` = a SECOND copy of the golden image, attached via
      QEMU's `nvme` device — a real NVMe controller, `removable == 0`,
      matching step 2's `/sys/block/nvme*n1` scan.
    - Because `nvme-target.raw` starts as a copy of the SAME golden image,
      it already carries `duduclaw-`-prefixed GPT partition labels, so the
      script takes the "already carries DuDuClaw OS partition labels —
      proceeding as an unattended re-flash/upgrade" branch (step 3, the
      `HAS_DUDUCLAW_LABEL` path) — NOT the blank-disk
      `duduclaw.install=yes` kernel-cmdline branch. That second branch is
      a HONEST, DELIBERATE gap this script does not exercise: the
      cmdline lives baked inside the UKI's `.cmdline` PE section (not a
      text file systemd-boot exposes for runtime edits) and reliably
      injecting it blind through TCG QEMU was judged not worth the
      complexity for this round — see docs/todo/TODO-H1-ISO-x86-installer.md.
      Both branches share 100% of the actual data-moving code (step 4
      onward: `dd` the whole boot disk onto the target, `partx -u`,
      `systemctl poweroff`), so this still exercises the exact write path
      a real blank-NVMe factory install would take.
    - A 1MiB "canary" pattern is written into `nvme-target.raw` BEFORE
      boot, well inside root-A's data region (byte offset picked safely
      past the ESP's max size and safely before the backup GPT at the
      disk's tail — see CANARY_OFFSET's own comment). After the install
      "completes" (QEMU exits on its own — the guest's own
      `systemctl poweroff` is what ends the VM; this script passes no
      `-no-shutdown`), the canary is checked again: if the real `dd` ran,
      that region is now byte-identical to `usb-boot.raw` at the same
      offset, not the canary pattern. A clean exit with the canary still
      intact would mean the install silently no-op'd — this check is
      exactly what tells those two states apart.

  Phase B (verify): a completely separate QEMU boot, `nvme-target.raw`
    ONLY (as an ordinary `virtio` boot disk — by this point it's just "a
    disk with DuDuClaw OS on it", no different from any other smoke-test
    disk; the `nvme`-device topology was only needed to satisfy Phase A's
    install-detection gate), with a virtio-gpu display attached so the
    detection-gated kiosk auto-starts (confirmed working under QEMU's
    virtual GPU — `crates/duduclaw-shell/BUILD-LINUX.md` Stage B-③, same
    mechanism `appliance/run-vm.sh`'s own VM_DISPLAY=gui path uses).
    Because this build does NOT ship `DUDUCLAW_SHELL_BIN_PATH`/
    `DUDUCLAW_COMP_BIN_PATH` (H1-ISO deliberately skipped the optional
    gpui shell/compositor to keep the first x86-64 bake's Rust build
    light — see build.sh's own "(1c)/(1d) ... unset" log lines), the
    kiosk falls back to the Chromium dashboard, which is what actually
    renders here: `web/src/pages/WelcomePage.tsx`'s first-run wizard,
    `welcome.hero.title` = "開始建立第一位 AI 員工吧" (zh-TW/en.json — a
    distinctive string, safe for a bare `wait_for_screen_contains`, same
    reasoning `q3_ocr_boot_accept.py` gives for its own OOBE string).

Usage:
    appliance/tests/lib/.venv/bin/python3 appliance/tests/lib/h1_x86_install_test.py [--keep-disks]
"""
from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from qmp_client import QmpClient  # noqa: E402
from screen_check import ScreenCheckResult, screen_contains  # noqa: E402
from test_run import TestFailure, TestRun  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
APPLIANCE_DIR = REPO_ROOT / "appliance"
# Deliberately NOT appliance/mkosi.output/duduclaw-os.raw by default:
# mkosi.output/ is a SHARED directory across every concurrent session baking
# any architecture (2026-08-24/25 incident — a concurrent arm64 rebake
# overwrote this exact x86-64 raw before it could be tested, twice, until
# the bake wrapper started moving the artifact out immediately on success).
# The isolated copy this line points at by default
# (appliance/.build/h1-x86/duduclaw-os.raw) is that rescued, stable copy.
# GOLDEN_RAW_OVERRIDE lets a caller point at a different raw explicitly
# (e.g. still testing straight out of mkosi.output/ for a quick local loop)
# without editing this file.
GOLDEN_RAW = Path(
    os.environ.get("GOLDEN_RAW_OVERRIDE", str(APPLIANCE_DIR / ".build" / "h1-x86" / "duduclaw-os.raw"))
)

WORK_DIR = APPLIANCE_DIR / ".vm" / "h1-x86-install"
USB_BOOT_RAW = WORK_DIR / "usb-boot.raw"
NVME_TARGET_RAW = WORK_DIR / "nvme-target.raw"
VARS_A = WORK_DIR / "vars-phase-a.fd"
VARS_B = WORK_DIR / "vars-phase-b.fd"

# x86-64 OVMF candidates — same search order appliance/run-vm.sh and
# smoke-qemu.sh already use for the x86-64 path (Homebrew qemu 11.1.0,
# confirmed real filenames per README.md's "Known open points").
OVMF_CODE_CANDS = [
    Path("/opt/homebrew/share/qemu/edk2-x86_64-code.fd"),
    Path("/usr/local/share/qemu/edk2-x86_64-code.fd"),
    Path("/usr/share/OVMF/OVMF_CODE.fd"),
]
OVMF_VARS_CANDS = [
    Path("/opt/homebrew/share/qemu/edk2-i386-vars.fd"),
    Path("/usr/local/share/qemu/edk2-i386-vars.fd"),
    Path("/usr/share/OVMF/OVMF_VARS.fd"),
]

# Assigned exclusively to this H1-ISO line (task brief: "你的 QEMU 用
# 47063/47064" — do not reuse duduclaw-lwm-exp's 47023-47062 range or any
# other appliance test's ports, e.g. ab-update's 47031/47032, Q3-OCR's
# 47045/47046). Both phases reuse the same pair sequentially — phase A's
# qemu process has fully exited (guest poweroff) before phase B starts,
# so there is never a live conflict.
SERIAL_PORT = 47063
QMP_PORT = 47064
DASHBOARD_PORT = 18820  # checked free via `lsof -iTCP -sTCP:LISTEN` at write time (18789/18793/
# 18799/18899 were all already bound by other concurrent sessions' VMs — this port collided
# with one of those on the first real run, see this file's own H1-ISO revision history)
VM_NAME_A = "duduclaw-os-h1-install-a"
VM_NAME_B = "duduclaw-os-h1-install-b"

# 3 GiB into the disk: ESP is sized 512M-1G (mkosi.repart/10-esp.conf), so
# 3GiB is comfortably inside root-A's data region regardless of exactly
# where ESP landed in that range, and comfortably before the backup GPT
# header at the very end of a 14.5G disk. 1MiB canary, not 1 byte, so a
# sparse-file hole-punch or a coarse-grained corruption check would still
# catch it.
CANARY_OFFSET = 3 * 1024 * 1024 * 1024
CANARY_LEN = 1024 * 1024
CANARY_PATTERN = b"H1CANARY" * (CANARY_LEN // 8)

# OOBE_TEXT_CANDIDATES, not a single OOBE_TEXT (2026-08-25 fix, first real
# Phase B run): the first live screenshot showed the OOBE wizard rendering
# in ENGLISH ("Let's create your first agent" / web/src/i18n/en.json
# welcome.hero.title), not zh-TW — this image's guest locale defaults to
# whatever Debian's stock locale is (no explicit zh-TW locale/LANG
# configuration in this recipe yet), so Chromium/the dashboard fall back to
# English. Same reasoning `q3_ocr_boot_accept.py` already established for
# its own desktop-vs-OOBE check: accept whichever real, OCR-recognizable
# state actually renders rather than asserting one specific locale. "your
# first agent" (no apostrophe — apostrophe glyphs are an OCR risk) is used
# instead of the full title for the same "safe against tail noise" reason
# the zh-TW string was originally trimmed for.
OOBE_TEXT_CANDIDATES = ["your first agent", "開始建立第一位"]


def wait_for_any_screen_contains(
    candidates: list[str], qmp: QmpClient, artifacts_dir: Path, *, timeout: float, interval: float
) -> ScreenCheckResult:
    """Like `screen_check.wait_for_screen_contains`, but accepts ANY of
    `candidates` as a pass (locale-agnostic OOBE check — see
    OOBE_TEXT_CANDIDATES' own comment for why more than one locale needs to
    be acceptable here). One screenshot per poll iteration, checked against
    every candidate in turn — not one screenshot per candidate — so this
    costs the same number of screendumps as a single-string wait."""
    deadline = time.time() + timeout
    last: ScreenCheckResult | None = None
    while True:
        # Reuse ONE screenshot across every candidate this iteration
        # (screen_contains takes an optional screenshot_path to skip
        # re-dumping) rather than one screendump per candidate per poll.
        first = screen_contains(candidates[0], qmp, artifacts_dir)
        if first.found:
            return first
        last = first
        for extra in candidates[1:]:
            r = screen_contains(extra, qmp, artifacts_dir, screenshot_path=first.screenshot_path)
            if r.found:
                return r
            last = r
        if time.time() >= deadline:
            return last
        time.sleep(interval)


def pick(cands: list[Path]) -> Path:
    for c in cands:
        if c.is_file():
            return c
    raise SystemExit(f"none of these exist: {', '.join(str(c) for c in cands)}")


def prepare_disks(fresh: bool) -> None:
    if not GOLDEN_RAW.is_file():
        raise SystemExit(
            f"golden image not found: {GOLDEN_RAW} — bake it first "
            f"(APPLIANCE_ARCH=x86-64, i.e. plain `appliance/build.sh`, the default)"
        )
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    if fresh:
        for p in (USB_BOOT_RAW, NVME_TARGET_RAW):
            if p.exists():
                p.unlink()
    for dest in (USB_BOOT_RAW, NVME_TARGET_RAW):
        if dest.exists():
            continue
        print(f"[h1-install] cloning {GOLDEN_RAW.name} -> {dest.name} (APFS cp -c)...")
        try:
            subprocess.run(["cp", "-c", str(GOLDEN_RAW), str(dest)], check=True)
        except subprocess.CalledProcessError:
            print(f"[h1-install] cp -c failed for {dest.name} (not on APFS?) — falling back to a plain copy", file=sys.stderr)
            shutil.copyfile(GOLDEN_RAW, dest)


def write_canary() -> None:
    with open(NVME_TARGET_RAW, "r+b") as f:
        f.seek(CANARY_OFFSET)
        f.write(CANARY_PATTERN)
    print(f"[h1-install] canary written at offset {CANARY_OFFSET} ({CANARY_LEN} bytes) in {NVME_TARGET_RAW.name}")


def canary_state() -> str:
    """Returns 'intact' (still the canary pattern — install never wrote
    here), 'overwritten-matches-source' (now byte-identical to the golden
    image at this offset — real dd happened), or 'overwritten-mismatch'
    (changed but doesn't match the source — something wrote here but not
    what we expected; report as evidence either way, never silently
    coerce to one of the other two)."""
    with open(NVME_TARGET_RAW, "rb") as f:
        f.seek(CANARY_OFFSET)
        cur = f.read(CANARY_LEN)
    if cur == CANARY_PATTERN:
        return "intact"
    with open(USB_BOOT_RAW, "rb") as f:
        f.seek(CANARY_OFFSET)
        src = f.read(CANARY_LEN)
    return "overwritten-matches-source" if cur == src else "overwritten-mismatch"


def boot_phase_a(code: Path, vars_tmpl: Path, log_path: Path, serial_log_path: Path) -> subprocess.Popen:
    shutil.copyfile(vars_tmpl, VARS_A)
    cmd = [
        "qemu-system-x86_64",
        "-name", VM_NAME_A,
        "-machine", "q35,accel=tcg", "-cpu", "max", "-smp", "4", "-m", "4096",
        "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
        "-drive", f"if=pflash,format=raw,file={VARS_A}",
        # USB boot media (the "USB stick"): usb-storage on qemu-xhci makes
        # the guest kernel see this as removable — exactly what
        # duduclaw-usb-install.sh's step 1 checks. `removable=true` is
        # LOAD-BEARING (2026-08-25 fix, first real run's root cause):
        # `qemu-system-x86_64 -device usb-storage,help` shows
        # `removable=<bool> - on/off (default: off)` — without this,
        # `/sys/block/*/removable` reads 0 in the guest even though the
        # disk is attached via usb-storage/qemu-xhci, so
        # duduclaw-usb-install.sh's step 1 correctly (per its own logic)
        # treated it as an ordinary non-removable boot disk and no-op'd —
        # confirmed via the guest's own console log: `unit=duduclaw-usb-
        # install ... res=success` at t=33s (the unit ran and exited 0
        # cleanly) followed by the boot continuing all the way to a normal
        # multi-user login prompt instead of powering off, and QEMU never
        # exiting within the (then-)1800s budget — a no-op success, not a
        # hang, and not a bug in duduclaw-usb-install.sh itself.
        "-device", "qemu-xhci,id=usb",
        "-drive", f"if=none,id=usbdisk,format=raw,file={USB_BOOT_RAW}",
        "-device", "usb-storage,drive=usbdisk,removable=true,bootindex=1",
        # Target NVMe (the "internal disk"): a real nvme controller,
        # non-removable, matching step 2's /sys/block/nvme*n1 scan.
        "-drive", f"if=none,id=nvmetarget,format=raw,file={NVME_TARGET_RAW}",
        "-device", "nvme,drive=nvmetarget,serial=duduclawh1target0,bootindex=2",
        "-netdev", f"user,id=net0,hostfwd=tcp:127.0.0.1:{DASHBOARD_PORT}-:18789",
        "-device", "virtio-net-pci,netdev=net0",
        "-display", "none",
        "-device", "virtio-gpu-pci",
        "-qmp", f"tcp:127.0.0.1:{QMP_PORT},server,nowait",
        # `file:` not `tcp:...,server,nowait` (2026-08-25 fix, first real
        # run's diagnostic gap): a TCP serial socket only shows output to
        # whoever CONNECTS and reads it, and phase A never connected a
        # reader — the first 1800s timeout produced zero evidence of
        # whether the guest even finished booting, let alone whether
        # duduclaw-usb-install.sh ever ran. `-serial file:PATH` makes QEMU
        # write the guest's console directly to a host file this script
        # (and a human) can tail live, no client needed.
        "-serial", f"file:{serial_log_path}",
        # Deliberately NO -no-shutdown: the guest's own `systemctl
        # poweroff` (the last line of duduclaw-usb-install.sh) is what
        # ends this QEMU process — that process exit IS the "install
        # finished" signal this script waits on.
    ]  # fmt: skip
    print(f"[h1-install] phase A (install): serial log -> {serial_log_path}   QMP -> 127.0.0.1:{QMP_PORT}")
    log_f = open(log_path, "w")
    return subprocess.Popen(cmd, stdout=log_f, stderr=subprocess.STDOUT)


def boot_phase_b(code: Path, vars_tmpl: Path, log_path: Path, serial_log_path: Path) -> subprocess.Popen:
    shutil.copyfile(vars_tmpl, VARS_B)
    cmd = [
        "qemu-system-x86_64",
        "-name", VM_NAME_B,
        "-machine", "q35,accel=tcg", "-cpu", "max", "-smp", "4", "-m", "4096",
        "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
        "-drive", f"if=pflash,format=raw,file={VARS_B}",
        # nvme-target.raw is now "just a disk with DuDuClaw OS on it" —
        # boot it the ordinary virtio-disk way, same as every other
        # appliance smoke test. (USB stick removed, per the real flow:
        # duduclaw-usb-install.sh's own log line tells the operator to do
        # exactly this before powering back on.)
        "-drive", f"if=virtio,format=raw,file={NVME_TARGET_RAW}",
        "-netdev", f"user,id=net0,hostfwd=tcp:127.0.0.1:{DASHBOARD_PORT}-:18789",
        "-device", "virtio-net-pci,netdev=net0",
        "-display", "none",
        "-device", "virtio-gpu-pci", "-device", "qemu-xhci,id=usb", "-device", "usb-tablet", "-device", "usb-kbd",
        "-qmp", f"tcp:127.0.0.1:{QMP_PORT},server,nowait",
        # file:, not tcp:...,server,nowait — same reasoning as phase A's
        # own comment: a file always captures the guest console whether or
        # not anything is actively connected to read it.
        "-serial", f"file:{serial_log_path}",
    ]  # fmt: skip
    print(f"[h1-install] phase B (verify boot): serial log -> {serial_log_path}   QMP -> 127.0.0.1:{QMP_PORT}   dashboard -> :{DASHBOARD_PORT}")
    log_f = open(log_path, "w")
    return subprocess.Popen(cmd, stdout=log_f, stderr=subprocess.STDOUT)


def wait_qmp_ready(host: str, port: int, timeout: float) -> QmpClient:
    deadline = time.time() + timeout
    last_err: Exception | None = None
    while time.time() < deadline:
        try:
            qmp = QmpClient(host, port, connect_timeout=3.0)
            qmp.connect()
            return qmp
        except Exception as e:  # noqa: BLE001 - QEMU may not have opened the QMP listener yet
            last_err = e
            time.sleep(1.0)
    raise SystemExit(f"QMP never came up on port {port} within {timeout}s: {last_err}")


def kill_if_alive(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def cleanup(keep_disks: bool) -> None:
    if keep_disks:
        print(f"[h1-install] --keep-disks set, leaving {WORK_DIR} in place")
        return
    for p in (USB_BOOT_RAW, NVME_TARGET_RAW, VARS_A, VARS_B):
        if p.exists():
            p.unlink()
    print(f"[h1-install] removed working disks under {WORK_DIR}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fresh", action="store_true", help="delete and re-clone both disks even if they exist")
    ap.add_argument("--keep-disks", action="store_true", help="don't delete the working disks after the run")
    ap.add_argument(
        "--install-timeout",
        type=float,
        default=7200.0,
        help=(
            "phase A: max seconds to wait for guest poweroff. Default 7200s (2h) — raised "
            "2026-08-25 after a real run's first two attempts hit the old 1800s (30min) ceiling: "
            "under full TCG software emulation, UEFI+kernel boot alone can take 5-10min and the "
            "self-install dd of a ~14.5GB disk through emulated USB+NVMe controllers can plausibly "
            "take 30-90min on top of that — 1800s was never enough budget, not a sign of a stuck VM"
        ),
    )
    ap.add_argument(
        "--checkpoint-interval",
        type=float,
        default=300.0,
        help="phase A: seconds between progress checkpoints (screendump + serial log size) while waiting — so a long wait is observed, not blind",
    )
    ap.add_argument(
        "--boot-timeout",
        type=float,
        default=1800.0,
        help="phase B: max seconds to wait for the OOBE text on screen (raised from 600s alongside phase A — same TCG-is-slow reasoning, this boot has no dd but still a full cold UEFI+kernel+userspace-to-Chromium boot)",
    )
    args = ap.parse_args()

    code = pick(OVMF_CODE_CANDS)
    vars_tmpl = pick(OVMF_VARS_CANDS)
    run = TestRun(name="h1-x86-install")
    print(f"[h1-install] artifacts -> {run.run_dir}")

    prepare_disks(fresh=args.fresh)
    write_canary()
    canary_before = canary_state()
    if canary_before != "intact":
        # Only possible on a reused (--fresh not passed, and a PRIOR run's
        # disk survived) nvme-target.raw whose canary write above should
        # have just re-planted the pattern — report loudly rather than
        # silently trusting a stale disk.
        print(f"[h1-install] WARNING: canary read back as {canary_before!r} immediately after writing it — unexpected", file=sys.stderr)

    proc_a: subprocess.Popen | None = None
    proc_b: subprocess.Popen | None = None
    qmp: QmpClient | None = None
    try:
        # --- Phase A: install -------------------------------------------
        serial_log_a = run.run_dir / "phase-a-serial.log"
        proc_a = boot_phase_a(code, vars_tmpl, run.run_dir / "phase-a-qemu.log", serial_log_a)
        print(
            f"[h1-install] phase A: waiting up to {args.install_timeout:.0f}s for the guest to self-install "
            f"and power off (checkpoint every {args.checkpoint_interval:.0f}s: serial log size + a screendump)..."
        )
        qmp_a: QmpClient | None = None
        deadline = time.time() + args.install_timeout
        last_serial_size = -1
        timed_out = False
        while True:
            rc = proc_a.poll()
            if rc is not None:
                print(f"[h1-install] phase A: QEMU exited on its own (rc={rc}) — guest-initiated poweroff, as expected on success")
                break
            if time.time() >= deadline:
                timed_out = True
                break
            time.sleep(min(args.checkpoint_interval, max(1.0, deadline - time.time())))
            if proc_a.poll() is not None:
                continue  # re-check at top of loop, print the exit line there instead of double-reporting
            serial_size = serial_log_a.stat().st_size if serial_log_a.exists() else 0
            grew = "growing" if serial_size > last_serial_size else "UNCHANGED since last checkpoint"
            last_serial_size = serial_size
            elapsed = args.install_timeout - (deadline - time.time())
            print(f"[h1-install] phase A checkpoint: t={elapsed:.0f}s serial_log={serial_size}B ({grew})")
            try:
                if qmp_a is None:
                    qmp_a = QmpClient("127.0.0.1", QMP_PORT, connect_timeout=3.0)
                    qmp_a.connect()
                qmp_a.screendump(str(run.run_dir / f"phase-a-checkpoint-{int(elapsed):06d}s.png"))
            except Exception as e:  # noqa: BLE001 - a failed checkpoint screenshot must never abort the wait itself
                print(f"[h1-install]   (checkpoint screendump failed, non-fatal: {e})")

        if qmp_a is not None:
            qmp_a.close()

        if timed_out:
            kill_if_alive(proc_a)
            serial_tail = ""
            try:
                serial_tail = serial_log_a.read_text(errors="replace")[-6000:]
            except OSError:
                pass
            run.fail(
                "phase-a-install",
                f"phase A did not power off within {args.install_timeout:.0f}s — either the install is still "
                f"running (TCG is genuinely slow) or duduclaw-usb-install.sh never reached its poweroff line "
                f"— see {serial_log_a} for the guest's actual console output",
                qmp=None,
                ocr_evidence=serial_tail or "(serial log empty or unreadable — see phase-a-qemu.log for QEMU's own stderr instead)",
            )

        canary_after = canary_state()
        print(f"[h1-install] canary state: before={canary_before!r} after={canary_after!r}")
        if canary_after != "overwritten-matches-source":
            run.fail(
                "phase-a-canary",
                f"expected canary to be overwritten to match the source disk after install (real dd write), "
                f"got {canary_after!r} instead — install either no-op'd or wrote something unexpected",
                qmp=None,
                ocr_evidence=serial_log_a.read_text(errors="replace")[-6000:] if serial_log_a.exists() else "(no serial log)",
            )
        print("[h1-install] PASS: phase A canary confirms a real whole-disk dd from usb-boot.raw onto nvme-target.raw")

        # --- Phase B: verify boot from the freshly "installed" disk -----
        proc_b = boot_phase_b(code, vars_tmpl, run.run_dir / "phase-b-qemu.log", run.run_dir / "phase-b-serial.log")
        qmp = wait_qmp_ready("127.0.0.1", QMP_PORT, timeout=30.0)
        print(f"[h1-install] phase B: QMP connected, waiting up to {args.boot_timeout:.0f}s for OOBE text {OOBE_TEXT_CANDIDATES!r}...")
        oobe = wait_for_any_screen_contains(OOBE_TEXT_CANDIDATES, qmp, run.run_dir, timeout=args.boot_timeout, interval=5.0)
        if not oobe.found:
            run.fail(
                "phase-b-oobe",
                f"none of {OOBE_TEXT_CANDIDATES!r} recognized on screen within {args.boot_timeout:.0f}s of boot "
                f"from the freshly-installed disk",
                qmp=qmp,
                ocr_evidence=oobe.evidence_text,
            )
        print(f"[h1-install] PASS: OOBE text found via OCR pass {oobe.matched_pass_label!r}, bbox={oobe.matched_bbox}")
        run.success("oobe", qmp)
    except TestFailure as e:
        print(f"[h1-install] FAIL: {e.reason}", file=sys.stderr)
        if e.screenshot_path:
            print(f"[h1-install]   screenshot: {e.screenshot_path}", file=sys.stderr)
        if e.evidence_path:
            print(f"[h1-install]   OCR evidence: {e.evidence_path}", file=sys.stderr)
        return 1
    finally:
        if qmp is not None:
            qmp.close()
        if proc_a is not None:
            kill_if_alive(proc_a)
        if proc_b is not None:
            kill_if_alive(proc_b)
        cleanup(keep_disks=args.keep_disks)

    print(f"[h1-install] ALL CHECKS PASSED (install + reboot-to-OOBE). Artifacts in {run.run_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
