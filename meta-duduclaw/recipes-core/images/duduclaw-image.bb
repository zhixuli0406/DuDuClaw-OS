# DuDuClaw OS — Y2-1 product image (five duduclaw-* Rust binaries on top of
# the Y1-1 minimal bring-up base).
#
# Extends duduclaw-image-minimal.bb via `require` (not a copy/paste) so the
# already-verified UKI/systemd-boot/QEMU boot contract from Y1-1 stays a
# single source of truth — this recipe only adds the Rust payload + its
# verification-time login affordance on top.

SUMMARY = "DuDuClaw OS product image (Y2-1) -- duduclaw-sysd + duduclaw payload"
DESCRIPTION = "${SUMMARY}. Built on the Y1-1 minimal image; adds whichever \
of the five duduclaw-* Rust binaries have a working Yocto recipe so far \
(see meta-duduclaw/recipes-duduclaw/*/PLAN.md and the Y2-1 handoff notes \
for per-binary status -- this image recipe only lists what actually \
builds, never speculative IMAGE_INSTALL entries for unfinished recipes)."
LICENSE = "MIT"

require recipes-core/images/duduclaw-image-minimal.bb

# Bring-up/verification-only: lets `root` log in on the serial console with
# no password so the QEMU dual-verification (sysd socket + gateway
# /healthz) in the Y2-1 handoff notes can actually run shell commands
# without provisioning a real user/SSH-key story first (that's separate,
# later product-layer work -- appliance/'s Debian line already has a real
# firstboot-provision flow to model it on, see appliance/mkosi.extra/usr/
# local/sbin/duduclaw-firstboot-provision.sh). MUST NOT ship with this on;
# tracked as an explicit TODO in the Y2-1 handoff, not silently dropped.
#
# `debug-tweaks` (the older Yocto convenience shorthand for this) is NOT a
# valid IMAGE_FEATURE on this release -- caught by actually running bitbake
# ("'debug-tweaks' in IMAGE_FEATURES is not a valid image feature", full
# valid list printed in the error). `serial-autologin-root` is this
# release's own explicit feature for exactly this bring-up need (auto-login
# root on the serial getty, no password prompt at all -- simpler than
# combining allow-root-login+empty-root-password+allow-empty-password).
#
# Y2-3 (2026-08-25) fix: `serial-autologin-root` alone does NOT work --
# read rootfs-postcommands.bbclass's own serial_autologin_root() gate
# directly (`bb.utils.contains("IMAGE_FEATURES", ['empty-root-password',
# 'serial-autologin-root'], ...)`, a list-form contains(), which requires
# ALL listed features present, not just this one). Without
# `empty-root-password` too, the getty autologin sed patch is silently
# skipped and the serial console falls back to a normal login prompt PAM
# would then reject anyway (no password set on root at all in
# core-image-minimal). Caught by reading the class before burning a boot
# cycle on a login prompt this recipe's own comment claimed didn't exist.
IMAGE_FEATURES += "serial-autologin-root empty-root-password"

# Y2-3 (2026-08-25) fix: this list was missing duduclaw-cli, the package
# that actually installs /usr/bin/duduclaw (and duduclaw-gateway.service,
# which execs it) -- duduclaw-sysd alone cannot satisfy this milestone's
# QEMU dual-verification (sysd socket + gateway /healthz), since there was
# no gateway binary in the image to begin with. Caught by actually trying
# the boot verification, not by re-reading the recipe.
IMAGE_INSTALL:append = " duduclaw-sysd duduclaw-cli"
