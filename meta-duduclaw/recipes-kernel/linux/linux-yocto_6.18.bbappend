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
