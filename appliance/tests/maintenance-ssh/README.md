# Maintenance SSH guest baseline

These scripts inspect a booted maintenance-SSH candidate through a serial
root shell. The guest needs POSIX sh and the image's BusyBox/systemd/nft tools,
not Python. Copy `guest-baseline.sh` and `validators.sh` together to a test
directory; the scripts never collect provider credentials, Admin passwords,
private keys, arbitrary process command lines or journal messages.

## Modes

```sh
# Read-only: no service starts, temporary files, key generation or firewall writes.
sh guest-baseline.sh --edition desktop --mode readonly
# Use --edition base for the base edition (a read-only root is not required there).

# Mutation opt-in: on a fresh disposable guest only, start dropbearkey.service.
# All remaining operations are the same read-only baseline checks.
sh guest-baseline.sh --edition desktop --mode create-host-key --fresh-guest
```

The baseline expects a closed maintenance window and an active helper socket.
A missing host key fails the read-only run; it is never silently created.
`create-host-key` invokes the real service, whose existing-key condition keeps
an already present key. It does not open SSH, install an authorized key, alter
the firewall, remove data or restart sysd/gateway. `--fresh-guest` is an operator
assertion, not automatic proof that the machine is disposable.

Output is tab-separated `PASS`, `FAIL`, `EVIDENCE`, `NOT_RUN` and `SUMMARY`
records. Failures return nonzero (bad arguments/root preconditions return 2).
Unavailable commands, unreadable properties, missing files and unknown formats
fail. The readiness marker must be exactly the two bytes `1\n`; a missing or
extra newline and NUL bytes are rejected using `cmp`, a required guest tool.
Values that might include secrets are not echoed on failure. Only the
public host-key SHA256 fingerprint is printed for comparison across boots.

The checks cover account uniqueness/password marker, supplementary groups,
shell/home, executables/readiness marker, rootfs authorized-key absence,
persistent `/data`, merged dropbear/helper settings, the sysd MainPID gate,
loaded nft input/output/egress/source sets, and `CONFIG_CGROUP_BPF=y` from the
running kernel's configuration. nft input policy is deliberately compared with
the complete shipped chain; intentional firewall changes require re-review of
the validator. ICMP set order and dynamic counter values are normalized.

## Verification boundary

**Real-guest execution: NOT_RUN.** Host validator tests are synthetic, not image,
QEMU, installed-disk or cloud acceptance. A PASS baseline does not prove BPF
enforcement, SSH login, forwarding denial, filtered logs, reboot persistence,
deadline/fallback execution, A/B upgrade or real source-address filtering.
Those remain separate live acceptance cases. After a second real boot, run the
read-only mode and compare its fingerprint with the first boot's evidence.

## Host checks

```sh
sh -n appliance/tests/maintenance-ssh/guest-baseline.sh
sh -n appliance/tests/maintenance-ssh/validators.sh
python3 appliance/tests/maintenance-ssh/test_validators.py
shellcheck -S warning appliance/tests/maintenance-ssh/*.sh
```

The Python runner is host-only. It tests strict argv/token matching, unsafe nft
variants, exact source-set membership, missing kernel evidence, the production
readiness function's exact-byte marker comparison, and refusal of
key-creation mode without opt-in. An independent checker and real guest run
are still required before reporting acceptance.
