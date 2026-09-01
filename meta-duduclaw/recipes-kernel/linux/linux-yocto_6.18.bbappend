# Machine-name aliasing fix — discovered during Y1-1 bring-up.
#
# oe-core's linux-yocto_6.18.bb hardcodes:
#   COMPATIBLE_MACHINE = "^(qemuarm|qemuarmv5|qemuarm64|qemux86|qemuppc|
#     qemuppc64|qemumips|qemumips64|qemux86-64|qemuriscv64|qemuriscv32|
#     qemuloongarch64)$"
# as a single anchored regex literal (not a per-machine-override variable),
# so `require conf/machine/qemux86-64.conf` in duduclaw-qemux86-64.conf does
# NOT make the kernel recipe consider our machine compatible — MACHINE is
# textually "duduclaw-qemux86-64", which the regex's `$` anchor rejects
# outright (`bitbake -e duduclaw-image-minimal` failed with "Nothing
# PROVIDES 'virtual/kernel'" until this file was added). This is the
# standard fix for this class of problem: extend the regex alternation via
# :append rather than touching the upstream recipe.
COMPATIBLE_MACHINE:append = "|^duduclaw-qemux86-64$"

# Y2-2 (2026-08-25): same class of fix, real-hardware machine. genericx86-64
# has no equivalent qemu-only anchored regex to fail against — it has an
# override-keyed assignment instead (meta-yocto-bsp's own
# `COMPATIBLE_MACHINE:genericx86-64 = "genericx86-64"`), which never applies
# to us for the identical reason KMACHINE's override didn't (see
# duduclaw-genericx86-64.conf's KMACHINE comment) — MACHINEOVERRIDES never
# contains bare "genericx86-64", only "duduclaw-genericx86-64". Net effect
# for our machine name is the same failure shape as the qemu case though:
# COMPATIBLE_MACHINE falls back to the base recipe's qemu-only regex, which
# "duduclaw-genericx86-64" also doesn't match. Same fix shape applies.
COMPATIBLE_MACHINE:append = "|^duduclaw-genericx86-64$"

# --- Driver + gaming config fragments (Y2-2, real-hardware machine only) ---
# Scoped via the :duduclaw-genericx86-64 override so duduclaw-qemux86-64's
# SRC_URI, and therefore its kernel sstate signature, is byte-identical to
# before this change — QEMU bring-up must not regress just because the
# real-hardware line grew fragments. Plain .cfg files (not .scc) are the
# standard kernel-yocto mechanism for config-only fragments with no feature
# dependency graph of their own — kernel-yocto.bbclass's find_sccs() treats
# any SRC_URI entry ending in .scc or .cfg as a config fragment to merge,
# see openembedded-core/meta/classes-recipe/kernel-yocto.bbclass. Grouped by
# hardware target per research/native-os-2026-08/kernel-self-maintain-
# 2026-08.md §2 (N305 / 8845HS) plus a third fragment for the six gaming
# requirements from that report's §2.3 (protocol addendum). Content and the
# per-symbol research citation live in each .cfg file's own header comment,
# not duplicated here.
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-yocto:"
SRC_URI:append:duduclaw-genericx86-64 = " \
    file://duduclaw-n305.cfg \
    file://duduclaw-8845hs.cfg \
    file://duduclaw-gaming.cfg \
"

# --- Live installer ISO squashfs support (Y18, 2026-08-28) ---
# Unscoped (both machines) — see duduclaw-live-squashfs.cfg's own header
# comment for the full root-cause writeup (live QEMU probe showed squashfs
# entirely absent from /proc/filesystems, breaking duduclaw-image-live's
# rootfs.img mount). This DOES change duduclaw-qemux86-64's kernel SRC_URI/
# sstate signature (unlike the genericx86-64-only fragments above), which
# is intentional and unavoidable: the QEMU machine is this ticket's own
# verification target.
SRC_URI:append = " file://duduclaw-live-squashfs.cfg"

# --- Android binder IPC support for Waydroid (CP-1 A1, 2026-08-30) ---
# Unscoped (both machines) — see duduclaw-binder.cfg's own header comment
# for the root cause (2026-08-30 G4 live QEMU probe: `modprobe
# binder_linux` fails, module not found, on 6.18.24-yocto-standard) and
# for why this follows the live-squashfs precedent above rather than the
# real-hardware-only N305/8845HS/gaming scoping: the probe that found the
# gap ran on duduclaw-qemux86-64 itself, and Waydroid is a general OS
# capability both machines need, not something specific to real target
# hardware.
SRC_URI:append = " file://duduclaw-binder.cfg"

# --- KVM host + docker container runtime support for the self-contained
# --- Windows VM path (CP-2 wave-1 B1, 2026-08-30) ---
# Unscoped (both machines) — see duduclaw-kvm.cfg and duduclaw-
# container.cfg's own header comments for the full sourcing/rationale
# writeup (DESIGN-app-compat-layer-2026-08.md §2.3 路 B: self-packaged
# dockur/windows VM + FreeRDP 3 RemoteApp). Same "both machines" logic as
# binder/live-squashfs above: the QEMU target exercises this wave's own
# fail-closed acceptance criteria (no nested KVM, by design), while real
# target hardware (N305/8845HS) is where the VM actually runs — neither
# is a real-hardware-only capability the way the N305/8845HS/gaming
# fragments are.
SRC_URI:append = " file://duduclaw-kvm.cfg"
SRC_URI:append = " file://duduclaw-container.cfg"

# --- Waydroid LXC bridge DHCP checksum-fill (CP-2 wave-2, 2026-08-31) ---
# Unscoped (both machines), same logic as binder above — the live QEMU
# trace that isolated the missing symbol ran on duduclaw-qemux86-64, and
# Waydroid networking is a general OS capability. One symbol; the full
# root-cause trace and the "this is the complete fix, not the first of
# several" verification live in the .cfg's own header comment.
SRC_URI:append = " file://duduclaw-waydroid-net.cfg"

# --- OS security line P0 (WS-3, 2026-09-01) ---------------------------
# DESIGN-os-security-line-2026-09.md §2 支柱一 A4 (nftables default-deny
# firewall) + A5 (Landlock/Yama LSM). Unscoped (both machines), same
# reasoning as binder/kvm/container/waydroid-net above: this is a general
# OS security capability the QEMU verification target and real target
# hardware both need identically, not something specific to either one.
# Full symbol-selection reasoning (what's added, what's deliberately
# deferred, and why) lives in each .cfg's own header comment — not
# duplicated here.
SRC_URI:append = " file://duduclaw-nftables.cfg"
SRC_URI:append = " file://duduclaw-lsm.cfg"
