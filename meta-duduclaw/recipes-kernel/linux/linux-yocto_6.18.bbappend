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
