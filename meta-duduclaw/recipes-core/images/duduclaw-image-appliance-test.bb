# DuDuClaw OS -- appliance image, QEMU-TEST variant. NEVER SHIP THIS.
#
# Identical to duduclaw-image-appliance.bb in every byte of payload except
# that the serial console logs in as root again (serial-autologin-root +
# empty-root-password), so QEMU harnesses (appliance/.vm/inject/
# serial_expect.py, appliance/tests/ab-update/y92_yocto_probe.py, the
# app-compat live-fire driver) can drive a root shell -- the exact
# "dedicated, non-shipped test credential mechanism" the shipping recipe's
# own Y14-A TESTABILITY NOTE recommends, replacing the twice-repeated
# "temporarily comment out the hardening line, rebuild, remember to restore
# it" ritual (2026-08-27 and 2026-08-28 both did this by hand; this recipe
# exists so nobody does it a third time).
#
# Mechanism: the shipping recipe's IMAGE_FEATURES:remove is guarded by
# DUDUCLAW_IMAGE_TEST_LOGIN (see its own comment for why a plain
# `IMAGE_FEATURES +=` in THIS file could never win against `:remove`).
# Setting it here, before the require, disarms the removal for this recipe
# only -- `bitbake -e duduclaw-image-appliance` remains hardened.
#
# Guardrails against this image leaking into a release:
#   - release-os.sh's DEFAULT_IMAGE is duduclaw-image-appliance; nothing in
#     the packaging/signing path references this recipe.
#   - The image name itself carries `-test`, so any artifact produced from
#     it is self-labeling.

DUDUCLAW_IMAGE_TEST_LOGIN = "1"

require duduclaw-image-appliance.bb

SUMMARY = "DuDuClaw OS appliance image -- QEMU-test variant (root serial autologin; never shipped)"

# wic only. The shipping recipe also emits tar.zst/ext4 companions (release
# packaging reads them); a QEMU harness boots the wic and nothing else, and
# the extra fstypes roughly double do_image_*'s peak disk in an already
# disk-constrained builder VM -- the 2026-08-29 compat round wedged the
# Docker VM twice at ~95% disk during exactly this image's assembly.
IMAGE_FSTYPES = "wic"
