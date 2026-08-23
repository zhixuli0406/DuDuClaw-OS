#!/usr/bin/env python3
"""H3a acceptance probe — runs inside a booted DuDuClaw OS VM over serial.

H3a is the "packages and layout" package of the A/B update work: it installs
the two binaries the update loop needs, fixes the sysupdate/repart/UKI naming,
and binds each UKI to its own root slot. It deliberately does NOT arm boot
counting (that is H3b). So the acceptance bar here is:

  1. The image still boots. Layout changes are the way this work turns a
     machine into a brick, so "reached multi-user.target" is the hard gate.
  2. Root really is mounted from slot A **via the UKI's baked
     root=PARTUUID=**, not by gpt-auto guessing from partition labels.
  3. `systemd-sysupdate list` runs and produces sensible output — proving the
     binary is present, the `.transfer` files are found, slot A is recognised
     as the installed version and slot B as the free slot.
  4. `systemd-bless-boot status` produces a meaningful answer rather than
     "command not found" — proving the binary is present. `clean` is the
     CORRECT answer at this stage (boot counting is off); `indeterminate` is
     what H3b will require after arming it.

Everything is reported, then asserted, so a failure shows the evidence rather
than just a verdict.

Usage:
  h3a_probe.py [host] [port] [root-password]
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

# The expect-style serial driver is shared with the other VM rounds. It lives
# under appliance/.vm/inject/, which is gitignored (that directory also holds
# multi-hundred-MB test binaries), so this resolves it at runtime and says so
# plainly when it is missing rather than failing on an ImportError.
# Promoting serial_expect.py into this committed tools/ tree is a tracked
# follow-up; duplicating it here would mean two drifting copies of the one
# piece of code every VM round depends on.
_APPLIANCE = Path(__file__).resolve().parent.parent.parent
_INJECT = _APPLIANCE / ".vm" / "inject" / "serial_expect.py"
if not _INJECT.exists():
    print(f"missing {_INJECT} — that helper is host-local (appliance/.vm is "
          f"gitignored); copy it from another checkout or VM round", file=sys.stderr)
    sys.exit(2)
_spec = importlib.util.spec_from_file_location("serial_expect", _INJECT)
if _spec is None or _spec.loader is None:  # pragma: no cover - environment guard
    print(f"cannot load {_INJECT}", file=sys.stderr)
    sys.exit(2)
serial_expect = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(serial_expect)


CHECKS: list[tuple[str, str]] = [
    ("boot-target", "systemctl is-system-running || true"),
    ("root-source", "findmnt -no SOURCE /"),
    ("root-partuuid", "lsblk -no PARTUUID $(findmnt -no SOURCE /)"),
    ("kernel-cmdline", "cat /proc/cmdline"),
    ("image-version", "grep -E '^IMAGE_(ID|VERSION)=' /usr/lib/os-release"),
    ("gpt-labels", "lsblk -o NAME,PARTLABEL,PARTUUID,SIZE /dev/vda"),
    # The ESP mount point is DISCOVERED, never assumed. systemd-gpt-auto-
    # generator mounts it at /boot on this image, not /efi — measured, after an
    # earlier version of this probe hardcoded /efi and "found" an empty
    # same-named directory sitting on the root filesystem. `bootctl -p` is the
    # authoritative answer and is what sysupdate's PathRelativeTo=esp resolves
    # to as well.
    ("esp-path", "bootctl -p 2>/dev/null || echo NONE"),
    ("esp-mount", "findmnt -no TARGET,SOURCE \"$(bootctl -p)\" || echo NOT-MOUNTED"),
    ("esp-ukis", "ls -la \"$(bootctl -p)\"/EFI/Linux/"),
    # Writability is tested against the REAL ESP: boot counting renames files
    # there, and a read-only ESP turns the whole mechanism into a silent no-op.
    ("esp-writable",
     "p=$(bootctl -p) && touch \"$p/.h3a-write-probe\" && echo WRITABLE && rm -f \"$p/.h3a-write-probe\" || echo READ-ONLY"),
    ("sdboot-features", "bootctl status 2>/dev/null | grep -i 'boot counting' || echo NO-BOOT-COUNTING-FEATURE"),
    ("sysupdate-binary", "test -x /usr/lib/systemd/systemd-sysupdate && echo PRESENT || echo MISSING"),
    # Debian puts systemd-sysupdate under /usr/lib/systemd, which is NOT on
    # any service's PATH. duduclaw-sysd spawns it as a bare `systemd-sysupdate`
    # (crates/duduclaw-sysd/src/dispatch.rs), so this is recorded to show
    # whether that call site can work as written. Fixing it is H3f's job.
    ("sysupdate-in-path", "command -v systemd-sysupdate || echo NOT-IN-PATH"),
    # The new packages ship an auto-update timer and a bootloader-updater.
    # An appliance must not start updating itself on a schedule behind the
    # gateway's back, so their enablement state is recorded explicitly.
    ("new-unit-state",
     "systemctl is-enabled systemd-sysupdate.timer systemd-sysupdate-reboot.timer "
     "systemd-boot-update.service systemd-boot-random-seed.service 2>&1 | tr '\\n' ' '"),
    ("sysupdate-list", "/usr/lib/systemd/systemd-sysupdate list 2>&1 | tail -20"),
    ("blessboot-binary", "test -x /usr/lib/systemd/systemd-bless-boot && echo PRESENT || echo MISSING"),
    ("blessboot-status", "/usr/lib/systemd/systemd-bless-boot status 2>&1"),
    ("repart-binary", "command -v systemd-repart || echo MISSING"),
    ("iproute2", "ip -brief link 2>&1 | head -5"),
    ("failed-units", "systemctl list-units --state=failed --no-legend --no-pager || true"),
    ("boot-time", "systemd-analyze 2>&1 | head -2"),
]


def main() -> int:
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 47031
    password = sys.argv[3] if len(sys.argv) > 3 else "duduclaw"

    console = serial_expect.Console(host, port)
    for _ in range(3):
        if serial_expect.ensure_shell(console, password):
            break
    else:
        print("FATAL: could not reach a root shell over serial")
        return 2

    results: dict[str, str] = {}
    for name, command in CHECKS:
        out = console.run(command, timeout=60).strip()
        results[name] = out
        print(f"===== {name} =====")
        print(out if out else "(no output)")
        print()

    # ---- assertions -----------------------------------------------------
    failures: list[str] = []

    def require(name: str, ok: bool, why: str) -> None:
        if not ok:
            failures.append(f"{name}: {why}\n      got: {results.get(name, '')!r}")

    require("boot-target",
            "running" in results["boot-target"] or "degraded" in results["boot-target"],
            "system never finished booting")

    require("root-source", results["root-source"].endswith("vda2"),
            "root is not slot A (/dev/vda2)")

    cmdline = results["kernel-cmdline"]
    m = re.search(r"root=PARTUUID=([0-9a-fA-F-]{36})", cmdline)
    require("kernel-cmdline", m is not None,
            "the running kernel cmdline has no root=PARTUUID= — root is still "
            "being picked by gpt-auto, so per-slot UKIs cannot bind kernel to root")
    if m:
        require("root-partuuid",
                results["root-partuuid"].strip().lower() == m.group(1).lower(),
                "the mounted root is not the partition the UKI's root=PARTUUID= names")

    require("gpt-labels", "duduclaw-os_" in results["gpt-labels"],
            "slot A's partition label is not the version string sysupdate matches on")
    require("gpt-labels", "_empty" in results["gpt-labels"],
            "slot B is not labelled _empty, so sysupdate has no free slot to write into")

    require("esp-path", results["esp-path"].strip() not in ("", "NONE"),
            "no ESP is mounted — the UKI transfer's PathRelativeTo=esp has "
            "nothing to resolve to, and boot counting has no filenames to rename")
    require("esp-ukis", re.search(r"duduclaw-os_[0-9]", results["esp-ukis"]) is not None,
            "the ESP's UKI is not named duduclaw-os_<version>*.efi, so the "
            "sysupdate UKI transfer's MatchPattern can never match it")
    require("esp-writable", "WRITABLE" in results["esp-writable"],
            "the ESP is not writable — sd-boot could not decrement a boot "
            "counter and systemd-bless-boot could not clear one, so boot "
            "counting would silently never do anything (H3b blocker)")
    require("sdboot-features", "NO-BOOT-COUNTING-FEATURE" not in results["sdboot-features"],
            "the installed sd-boot does not advertise boot counting support")

    require("sysupdate-binary", results["sysupdate-binary"] == "PRESENT",
            "systemd-sysupdate is not in the image (duduclaw-sysd's "
            "SysupdateStatus/SysupdateApply verbs would fail to spawn)")
    require("sysupdate-list", "Failed" not in results["sysupdate-list"]
            and "No transfer" not in results["sysupdate-list"],
            "systemd-sysupdate list errored or found no transfer definitions")
    require("sysupdate-list", "VERSION" in results["sysupdate-list"],
            "systemd-sysupdate list printed no version table")

    require("blessboot-binary", results["blessboot-binary"] == "PRESENT",
            "systemd-bless-boot is not in the image — nothing could ever mark a "
            "boot successful, so boot counting must stay off")
    # `clean` = boot counting not in use, which is exactly right for H3a.
    # H3b flips this expectation to `indeterminate`.
    # Whole-word match: bless-boot prints exactly one of these four states.
    bless_words = set(re.findall(r"[a-z]+", results["blessboot-status"].lower()))
    require("blessboot-status",
            bool(bless_words & {"clean", "indeterminate", "good", "bad"}),
            "systemd-bless-boot status gave no recognisable state")

    # Token equality, NOT `"enabled" in ...` — "disabled" contains "enabled",
    # so a substring test here would fail on the correct answer. (Same trap the
    # project's coding conventions call out for security/routing checks.)
    unit_states = results["new-unit-state"].split()
    require("new-unit-state", "enabled" not in unit_states,
            "one of the update timers / bootloader updaters shipped by the new "
            "packages is enabled — an appliance must not update itself on a "
            "schedule outside the gateway's control")

    require("repart-binary", "MISSING" not in results["repart-binary"],
            "systemd-repart is absent — duduclaw-firstboot-repart.service cannot "
            "grow /data on real hardware")
    require("iproute2", "command not found" not in results["iproute2"],
            "iproute2 is absent — no `ip` for field diagnosis")

    print("=" * 60)
    if failures:
        print(f"H3A PROBE: FAIL ({len(failures)} assertion(s))")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("H3A PROBE: PASS (all assertions)")
    print(f"  bless-boot status = {results['blessboot-status'].strip()!r} "
          "(expected 'clean' in H3a: boot counting is deliberately not armed yet)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
