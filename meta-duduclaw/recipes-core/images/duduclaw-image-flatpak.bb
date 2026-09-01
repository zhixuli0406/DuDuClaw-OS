# DuDuClaw OS — Y3-2 Flatpak carriage milestone image.
#
# Layers on top of duduclaw-image.bb (Y2-3: sysd + gateway/cli payload) via
# `require`, same additive pattern as duduclaw-image.bb itself layering on
# duduclaw-image-minimal.bb. This is a SEPARATE image recipe, not an append
# to duduclaw-image.bb directly, so the already-verified Y2-3 dual-verify
# boot contract (sysd socket + gateway /healthz) stays reachable and
# buildable on its own without paying for Flatpak's ~real disk/build-time
# cost on every Y2-line rebuild.
#
# Scope (map decision ③, research/native-os-2026-08/flatpak-carrier-2026-08.md):
# proves the Flatpak/bubblewrap/ostree/polkit chain builds and boots under
# Yocto, and that a dbus-run-session-wrapped Chromium flatpak run reaches
# --kiosk under QEMU. As of Y3-2 this did NOT wire into duduclaw-kiosk.service
# (that service, and duduclaw-comp/duduclaw-shell themselves, had no Yocto
# recipe yet). STALE AS OF Y3-1/Y4-0/Y5-2: duduclaw-image.bb (required
# below) now pulls in duduclaw-comp + duduclaw-shell, duduclaw-kiosk.service
# is real and auto-enabled, and duduclaw-flatpak-kiosk-verify.bb's own
# duduclaw-steam-kiosk-verify.service (Y5-2) IS a real Wayland client of
# that kiosk service -- see this recipe's IMAGE_INSTALL comment below and
# duduclaw-flatpak-kiosk-verify.bb for the up-to-date picture. See
# kas/duduclaw-os.yml's meta-openembedded pin-rationale comment for the
# exact recipe versions this pulls in.

SUMMARY = "DuDuClaw OS Flatpak-carriage image (Y3-2, extended Y5-2 with Steam/kiosk verification) -- Flatpak/bubblewrap/ostree/polkit"
DESCRIPTION = "${SUMMARY}. Built on the Y2-3 product image; adds the \
Flatpak app-carriage chain (decision ③) plus the duduclaw-polkit-flatpak \
OS-side permission rule and (Y5-2) the duduclaw-steam-devices udev rule. \
duduclaw-image.bb (required below) already carries duduclaw-comp/-shell \
and duduclaw-kiosk.service as of Y3-1/Y4-0 -- see \
meta-duduclaw/recipes-duduclaw/duduclaw-flatpak-kiosk-verify/ for the \
Steam-reaches-its-login-screen verification this image now also carries."
LICENSE = "MIT"

# Y9-1 (2026-08-27): rebased from duduclaw-image.bb onto duduclaw-image-data.bb
# (which itself just `require`s duduclaw-image.bb + adds a /data partition +
# first-boot provisioning -- see that recipe's own header). This is the ONE
# line that changed to bring /data to this image: everything Y3-Y8 already
# proved here (Flatpak/Steam/kiosk/fcitx5-IME/network/audio) is untouched,
# since duduclaw-image-data.bb changes nothing about duduclaw-image.bb
# itself, only adds a WKS_FILE override + one more IMAGE_INSTALL entry on
# top of it. Motivation: Y8-2 (2026-08-27) found this exact image family
# has ZERO /data provisioning today -- fcitx5/libchewing's own per-user
# dictionary can never persist across a reboot, nor can the gateway's
# config.toml/device identity, because there is nowhere durable to put them
# (root:root 0755 `/` refuses even `mkdir` from the unprivileged
# duduclaw-kiosk account). duduclaw-image-ab.bb (Y8-1's separate, NOT YET
# boot-verified A/B mechanism) also has a /data partition, but gating this
# much more basic fix behind that unrelated mechanism's own verification
# bar would have blocked this image's active IME/kiosk work for no reason
# -- see duduclaw-image-data.bb's own header for the full argument.
require recipes-core/images/duduclaw-image-data.bb

# Y14-A (2026-08-27): the flatpak/Steam/Chromium IMAGE_INSTALL block +
# IMAGE_ROOTFS_EXTRA_SPACE this recipe carried inline since Y3-2/Y6-3 moved
# verbatim into a shared `.inc` so duduclaw-image-appliance.bb (the new A/B +
# full-payload convergence image, see
# commercial/docs/DESIGN-image-convergence-2026-08.md) can `require` the
# exact same package list without also `require`-ing this file's own
# `require recipes-core/images/duduclaw-image-data.bb` chain (which pulls in
# `inherit duduclaw-data-partflags`, a 3-partition assumption incompatible
# with the A/B line's 4-partition one). Zero behavior change here:
# `bitbake -e` before/after this edit was diffed and IMAGE_INSTALL's/
# IMAGE_ROOTFS_EXTRA_SPACE's final expansion is byte-identical.
require recipes-core/images/duduclaw-image-flatpak.inc

# IMAGE_FEATURES used to carry serial-autologin-root + empty-root-password
# unconditionally from duduclaw-image.bb (Y2-3) -- this milestone's QEMU
# verification (item 3: flatpak remote-add + install + dbus-run-session-
# wrapped --kiosk launch) was run as an interactive shell over that same
# serial console, no separate feature needed here.
#
# WS-3/A1 (2026-09-01, DESIGN-os-security-line-2026-09.md): this was a real
# G4 gap -- unlike duduclaw-image-appliance.bb, this recipe never removed
# the two tokens again, so a plain `bitbake duduclaw-image-flatpak` shipped
# root-serial-autologin-with-no-password with no override at all. Fixed at
# the source (duduclaw-image.bb's own IMAGE_FEATURES line is now gated
# behind DUDUCLAW_IMAGE_TEST_LOGIN, default off) rather than here, so this
# file needs no edit to inherit the safe default -- manual QEMU
# verification of this recipe now needs an explicit
# `DUDUCLAW_IMAGE_TEST_LOGIN=1` (local.conf or `bitbake -D`) to get the
# interactive shell back.
