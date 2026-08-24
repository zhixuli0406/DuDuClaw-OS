#!/usr/bin/env python3
"""Host resource guard: how many `qemu-system-aarch64` VMs are already
running on THIS machine right now.

Every appliance VM session shares one host (16GB RAM, `-m 4096` per VM) —
the working convention across the 2026-08 wave-5 sessions is to check
`ps aux | grep qemu` before booting another one and wait if two are
already up, rather than trust the host to gracefully degrade under a third
or fourth concurrent VM. This module turns that manual discipline into a
reusable, scriptable check, so a boot script can refuse to start (or poll
until it's safe) instead of a human having to remember to look first.
"""
from __future__ import annotations

import subprocess
import time


def count_running_qemu() -> int:
    proc = subprocess.run(["pgrep", "-f", "qemu-system-aarch64"], capture_output=True, text=True)
    if proc.returncode not in (0, 1):  # 1 = no processes matched, not an error here
        raise RuntimeError(f"pgrep failed: {proc.stderr.strip()}")
    lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
    return len(lines)


class VmBudgetExceeded(RuntimeError):
    pass


def ensure_vm_budget(max_other_running: int = 1) -> int:
    """Raises `VmBudgetExceeded` if more than `max_other_running` VMs are
    already up. Returns the current count on success. Call this
    IMMEDIATELY before booting a new VM (not once at script start) — the
    count can change while a script is doing unrelated setup work."""
    n = count_running_qemu()
    if n > max_other_running:
        raise VmBudgetExceeded(
            f"{n} qemu-system-aarch64 processes already running (budget: {max_other_running}) "
            "— wait for one to exit before booting another. `ps aux | grep qemu-system` to see which."
        )
    return n


def wait_for_vm_budget(max_other_running: int = 1, timeout: float = 1800.0, interval: float = 20.0) -> bool:
    """Poll `ensure_vm_budget` until it stops raising or `timeout` elapses.
    Returns True if the budget was satisfied within the timeout, False if
    it timed out still over budget (bounded — never loops forever)."""
    deadline = time.time() + timeout
    while True:
        try:
            ensure_vm_budget(max_other_running)
            return True
        except VmBudgetExceeded:
            if time.time() >= deadline:
                return False
            time.sleep(interval)


if __name__ == "__main__":
    print(f"qemu-system-aarch64 processes currently running: {count_running_qemu()}")
