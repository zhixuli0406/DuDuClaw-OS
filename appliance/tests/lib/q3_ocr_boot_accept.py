#!/usr/bin/env python3
"""Q3-OCR real acceptance flow: boot → `screen_contains` verifies real
desktop chrome text → `assert_no_failed_units`. The one flow the Q3-OCR
work order asked to be wired end-to-end onto the new helper library (the
other three appliance/tests/ suites — ab-update, wifi-hwsim — are
untouched, per the work order's "既有測試腳本不強制改寫" instruction).

Clones `appliance/.vm/duduclaw-os-vm.raw` via `cp -c` (APFS copy-on-write
clone, same pattern `appliance/.vm/inject/boot-cd4.sh` already uses), boots
it standalone on dedicated ports, and tears the clone down afterward —
never touches the shared disk itself, never touches any other session's VM.

**Live-corrected assumption (2026-08-24, this script's own first two real
runs)**: an earlier draft of this doc assumed the shared disk is always
past OOBE (based on `boot-vmround.sh`'s own comment that ITS particular
persistent copy has OOBE completed). Two consecutive `cp -c` clones of the
CURRENT `duduclaw-os-vm.raw`, taken minutes apart, landed in two DIFFERENT
states — one booted straight to the desktop, the other to the OOBE
language-picker — because the master file is, by every other session's own
description, "另一個 session 的長期工作磁碟" and gets rebuilt/reset by
whichever session is using it that hour. So this flow checks for EITHER
`DESKTOP_TEXT` ("DuDuClaw" brand mark) OR `OOBE_TEXT` ("選擇語言" heading)
— whichever the clone actually landed on is a legitimate, real UI state to
prove `screen_contains` against, and either one is real end-to-end evidence
the compositor painted real, OCR-recognizable text after a genuine boot.
Driving a full OOBE click-through (codrive keyboard/mouse injection to
reach the desktop deterministically) is a different, much larger work
package and stays out of this round's scope.

Usage:
    appliance/tests/lib/.venv/bin/python3 appliance/tests/lib/q3_ocr_boot_accept.py [--keep-clone] [--fresh-clone]
"""
from __future__ import annotations

import argparse
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from screen_check import wait_for_layer_on_screen, wait_for_screen_contains  # noqa: E402
from qmp_client import QmpClient  # noqa: E402
from serial_console import DEFAULT_ROOT_PASSWORD, SerialConsole, ensure_shell  # noqa: E402
from test_run import TestFailure, TestRun  # noqa: E402
from vm_budget import ensure_vm_budget, VmBudgetExceeded  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
VM_DIR = REPO_ROOT / "appliance" / ".vm"
MASTER_DISK = VM_DIR / "duduclaw-os-vm.raw"
CLONE_DISK = VM_DIR / "duduclaw-os-w53.raw"
VARS_FILE = VM_DIR / "vars-w53.fd"
VARS_TEMPLATE = Path("/opt/homebrew/share/qemu/edk2-arm-vars.fd")
UEFI_CODE = Path("/opt/homebrew/share/qemu/edk2-aarch64-code.fd")

DESKTOP_TEXT = "DuDuClaw"  # top-left brand mark in the session shell's menu bar
# Region the brand mark actually renders in, per a real reference screenshot
# (appliance/.vm/d9lock/10-home.png: OCR bbox (34, 10, 66, 9)) — deliberately
# NOT plain screen_contains: see wait_for_layer_on_screen's own doc for the
# false-positive this geometry check exists to rule out (a systemd unit
# description containing the literal substring "DuDuClaw", OCR'd off the
# boot-time text console before the compositor ever starts).
DESKTOP_TEXT_REGION = (0, 0, 150, 30)
OOBE_TEXT = "選擇語言"  # OOBE language-picker heading — distinctive enough
# that a plain screen_contains (no geometry) is safe: this exact zh-TW
# string does not appear anywhere in the (English) kernel/systemd boot log.

SERIAL_PORT = 47045
QMP_PORT = 47046
VNC_DISPLAY = 6  # -> 127.0.0.1:5906, not already used by any boot-*.sh in appliance/.vm/inject/
DASHBOARD_PORT = 18798  # not already used by any boot-*.sh in appliance/.vm/inject/
VM_NAME = "duduclaw-os-vm-w53"


def clone_disk(fresh: bool) -> None:
    if fresh and CLONE_DISK.exists():
        CLONE_DISK.unlink()
    if not CLONE_DISK.exists():
        if not MASTER_DISK.exists():
            raise SystemExit(f"master disk not found: {MASTER_DISK} (build/run it first — see appliance/build.sh)")
        print(f"[w53] cloning {MASTER_DISK.name} -> {CLONE_DISK.name} (APFS cp -c)...")
        try:
            subprocess.run(["cp", "-c", str(MASTER_DISK), str(CLONE_DISK)], check=True)
        except subprocess.CalledProcessError:
            print("[w53] cp -c failed (not on APFS?) — falling back to a plain copy", file=sys.stderr)
            shutil.copyfile(MASTER_DISK, CLONE_DISK)
    shutil.copyfile(VARS_TEMPLATE, VARS_FILE)  # UEFI varstore always reset fresh — see boot-firstrun.sh's own note


def boot_qemu(log_path: Path) -> subprocess.Popen:
    cmd = [
        "qemu-system-aarch64",
        "-name", VM_NAME,
        "-machine", "virt,accel=hvf", "-cpu", "host", "-smp", "4", "-m", "4096",
        "-drive", f"if=pflash,format=raw,readonly=on,file={UEFI_CODE}",
        "-drive", f"if=pflash,format=raw,file={VARS_FILE}",
        "-drive", f"if=virtio,format=raw,file={CLONE_DISK}",
        "-netdev", f"user,id=net0,hostfwd=tcp:127.0.0.1:{DASHBOARD_PORT}-:18789",
        "-device", "virtio-net-pci,netdev=net0",
        "-display", "none",
        "-device", "virtio-gpu-pci", "-device", "qemu-xhci,id=usb", "-device", "usb-tablet", "-device", "usb-kbd",
        "-vnc", f"127.0.0.1:{VNC_DISPLAY}",
        "-qmp", f"tcp:127.0.0.1:{QMP_PORT},server,nowait",
        "-serial", f"tcp:127.0.0.1:{SERIAL_PORT},server,nowait",
    ]  # fmt: skip
    print(f"[w53] serial -> 127.0.0.1:{SERIAL_PORT}   QMP -> 127.0.0.1:{QMP_PORT}   dashboard -> :{DASHBOARD_PORT}")
    log_f = open(log_path, "w")
    return subprocess.Popen(cmd, stdout=log_f, stderr=subprocess.STDOUT)


def wait_qmp_ready(host: str, port: int, timeout: float = 30.0) -> QmpClient:
    deadline = time.time() + timeout
    last_err: Exception | None = None
    while time.time() < deadline:
        try:
            qmp = QmpClient(host, port, connect_timeout=3.0)
            qmp.connect()
            return qmp
        except Exception as e:  # noqa: BLE001 - broad on purpose: QEMU may not have opened the QMP listener yet
            last_err = e
            time.sleep(1.0)
    raise SystemExit(f"QMP never came up on port {port} within {timeout}s: {last_err}")


def teardown(proc: subprocess.Popen, keep_clone: bool) -> None:
    print("[w53] tearing down...")
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
    if not keep_clone:
        for p in (CLONE_DISK, VARS_FILE):
            if p.exists():
                p.unlink()
                print(f"[w53] removed {p}")
    else:
        print(f"[w53] --keep-clone set, leaving {CLONE_DISK} and {VARS_FILE} in place")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--fresh-clone", action="store_true", help="delete and re-clone the disk even if it exists")
    ap.add_argument("--keep-clone", action="store_true", help="don't delete the clone disk/vars after the run")
    ap.add_argument("--boot-timeout", type=float, default=120.0)
    ap.add_argument(
        "--root-password",
        default=DEFAULT_ROOT_PASSWORD,
        help="root password to try over serial for the systemd-unit check (default: the project convention "
        "'duduclaw' — but a STOCK clone of duduclaw-os-vm.raw has no root password at all; see "
        "serial_console.py's module doc. That check is skipped gracefully, not treated as a failure, "
        "when login never succeeds.",
    )
    ap.add_argument(
        "--max-other-vms",
        type=int,
        default=1,
        help=(
            "refuse to boot if more than this many OTHER qemu-system-aarch64 processes are already "
            "running (default 1, i.e. wait until we'd be at most the 2nd VM). The work order's own "
            "environment note phrases the check as 'before booting, confirm currently-running VMs are "
            "<=2' — pass --max-other-vms=2 to use that literal precondition (we'd become the 3rd) "
            "instead of the stricter default."
        ),
    )
    args = ap.parse_args()

    try:
        n = ensure_vm_budget(max_other_running=args.max_other_vms)
        print(f"[w53] VM budget OK: {n} other qemu VM(s) running, safe to add ours (total {n + 1})")
    except VmBudgetExceeded as e:
        print(f"[w53] REFUSING to boot: {e}", file=sys.stderr)
        return 1

    run = TestRun(name="q3-ocr-boot-accept")
    print(f"[w53] artifacts -> {run.run_dir}")

    clone_disk(fresh=args.fresh_clone)
    proc = boot_qemu(run.run_dir / "qemu.log")
    qmp: QmpClient | None = None
    try:
        qmp = wait_qmp_ready("127.0.0.1", QMP_PORT)
        print("[w53] QMP connected, waiting for real, OCR-recognizable UI text (desktop OR OOBE)...")

        half = args.boot_timeout / 2
        # Desktop check goes through layer_on_screen (geometry-scoped, not
        # plain screen_contains) — see DESKTOP_TEXT_REGION's own comment for
        # why: a bare substring match on "DuDuClaw" can true-positive against
        # the boot-time TEXT CONSOLE's own systemd unit descriptions, before
        # the compositor has even started.
        desktop = wait_for_layer_on_screen(
            DESKTOP_TEXT, DESKTOP_TEXT_REGION, qmp, run.run_dir, timeout=half, interval=3.0
        )
        if desktop.ok:
            print(f"[w53] PASS: {DESKTOP_TEXT!r} found in menu-bar region, bbox={desktop.screen.matched_bbox}")
            run.success("boot-text", qmp)
        else:
            oobe = wait_for_screen_contains(OOBE_TEXT, qmp, run.run_dir, timeout=half, interval=3.0)
            if not oobe.found:
                combined_evidence = (
                    f"=== desktop check ({DESKTOP_TEXT!r} in {DESKTOP_TEXT_REGION}): {desktop.check} ===\n"
                    f"{desktop.screen.evidence_text}\n\n"
                    f"=== OOBE check ({OOBE_TEXT!r}, no geometry): not_found ===\n{oobe.evidence_text}"
                )
                run.fail(
                    "boot-text",
                    f"neither desktop brand mark ({desktop.check}) nor OOBE heading recognized "
                    f"within {args.boot_timeout}s of boot",
                    qmp=qmp,
                    ocr_evidence=combined_evidence,
                )
            print(f"[w53] PASS: {OOBE_TEXT!r} found via OCR pass {oobe.matched_pass_label!r}, bbox={oobe.matched_bbox}")
            run.success("boot-text", qmp)

        console = SerialConsole("127.0.0.1", SERIAL_PORT)
        systemd_check_skipped = False
        try:
            if not ensure_shell(console, args.root_password):
                # NOT a TestFailure: a stock (non-APPLIANCE_DEBUG) clone of
                # `duduclaw-os-vm.raw` ships with NO root password at all
                # (see serial_console.py's module doc — live-confirmed via
                # PAM's own `res=failed` audit line, matching `commercial/
                # docs/DESIGN-ab-update-rollback-2026-08.md` §11.6's
                # same-day finding). That's an environment precondition,
                # not a regression this test caught — report it as an
                # honest skip, distinct from both PASS and FAIL, rather
                # than either hide it or misreport it as the same kind of
                # failure a real stuck/broken unit would be.
                systemd_check_skipped = True
                shot = run.run_dir / "skip-serial-login.png"
                qmp.screendump(str(shot))
                print(
                    "[w53] SKIP: no root shell over serial — this clone has no root password set "
                    "(expected on a stock, non-APPLIANCE_DEBUG image; pass --root-password if this "
                    "disk had one injected, e.g. via ab-update/inject-binaries.sh's AB_ROOT_PASSWORD)"
                )
            else:
                failed = run.assert_no_failed_units(console, exempt=[], qmp=qmp)
                print(f"[w53] PASS: systemctl --failed reported {len(failed)} unit(s) (all exempted or none)")
        finally:
            console.close()

        if systemd_check_skipped:
            print(f"[w53] DESKTOP CHECK PASSED, SYSTEMD CHECK SKIPPED (see above). Artifacts in {run.run_dir}")
            return 2  # distinct exit code: neither clean pass (0) nor a caught failure (1)
        print(f"[w53] ALL CHECKS PASSED. Artifacts in {run.run_dir}")
        return 0
    except TestFailure as e:
        print(f"[w53] FAIL: {e.reason}", file=sys.stderr)
        if e.screenshot_path:
            print(f"[w53]   screenshot: {e.screenshot_path}", file=sys.stderr)
        if e.evidence_path:
            print(f"[w53]   OCR evidence: {e.evidence_path}", file=sys.stderr)
        return 1
    finally:
        if qmp is not None:
            qmp.close()
        teardown(proc, keep_clone=args.keep_clone)


if __name__ == "__main__":
    sys.exit(main())
