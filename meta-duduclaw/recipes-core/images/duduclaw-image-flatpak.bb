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
# --kiosk under QEMU. It does NOT wire this into duduclaw-kiosk.service --
# that service (and duduclaw-comp/duduclaw-shell themselves) have no Yocto
# recipe yet (Y2-3 status table), so there is nothing to wire it into on
# this line yet. See kas/duduclaw-os.yml's meta-openembedded pin-rationale
# comment for the exact recipe versions this pulls in.

SUMMARY = "DuDuClaw OS Flatpak-carriage image (Y3-2) -- Flatpak/bubblewrap/ostree/polkit"
DESCRIPTION = "${SUMMARY}. Built on the Y2-3 product image; adds the \
Flatpak app-carriage chain (decision ③) plus the duduclaw-polkit-flatpak \
OS-side permission rule, but does not yet include duduclaw-comp/-shell \
(no Yocto recipe as of Y2-3) or the production duduclaw-kiosk.service \
wiring -- see meta-duduclaw/recipes-duduclaw/duduclaw-polkit-flatpak/ and \
the Y3-2 TODO row for exact scope and known follow-up work."
LICENSE = "MIT"

require recipes-core/images/duduclaw-image.bb

# dbus: flatpak's own SystemHelper D-Bus activation AND the D-Bus session
# bus the kiosk launch wrapper needs (research spike §1.2 point 1 --
# "D-Bus session bus 從錦上添花升級為地基" once the kiosk fallback itself
# is Flatpak Chromium). Not pulled in transitively by core-image-minimal.
#
# flatpak/bubblewrap/ostree: three of the four-piece carriage set, all
# resolved from meta-oe (see kas pin-rationale comment).
#
# xdg-desktop-portal is DELIBERATELY DROPPED from this milestone -- a real
# build-time discovery, not the original plan: `bitbake -e` failed with
# "Nothing PROVIDES 'pipewire'" (xdg-desktop-portal_1.20.4.bb's DEPENDS is
# unconditional -- json-glib/glib-2.0/flatpak/libportal/geoclue/pipewire/
# fuse3, no PACKAGECONFIG gate to drop pipewire). `pipewire` lives in
# meta-multimedia, a DIFFERENT meta-openembedded sublayer than meta-oe (one
# hand-checked via GitHub code search against the pinned commit, same as
# every other version claim in this layer). Pulling in a second sublayer
# just to satisfy a portal-frontend build dependency is not worth it for
# THIS milestone: the research spike (flatpak-carrier-2026-08.md §2.2)
# already proved the kiosk path works with ZERO portal packages installed
# ("全程零 xdg-desktop-portal / xdg-desktop-portal-gtk 安裝"). Tracked as
# follow-up (add meta-multimedia, or find/patch a pipewire-free
# PACKAGECONFIG path) whenever a real desktop-portal consumer (file
# choosers, screen share) actually needs it -- not blocking Y3-2's own
# scope (kiosk mechanism + OS permission foundation).
#
# duduclaw-polkit-flatpak: this layer's own OS-side permission rule (item 4
# of the Y3-2 ticket) -- see that recipe for the full reasoning on why it
# does not just reuse flatpak's stock wheel-group rule unchanged.
IMAGE_INSTALL:append = " \
    dbus \
    flatpak \
    bubblewrap \
    ostree \
    duduclaw-polkit-flatpak \
    duduclaw-flatpak-kiosk-verify \
"

# IMAGE_FEATURES already carries serial-autologin-root + empty-root-password
# from duduclaw-image.bb (Y2-3) -- this milestone's QEMU verification (item
# 3: flatpak remote-add + install + dbus-run-session-wrapped --kiosk launch)
# is run as an interactive shell over that same serial console, no separate
# feature needed here.

# --- Disk headroom for a LIVE Flathub Chromium install at runtime --------
# wic's efi-uki-bootdisk.wks.in has no fixed --size on the root partition
# (`part / --source rootfs ...`) -- it auto-sizes off IMAGE_ROOTFS_SIZE,
# which is computed from what IMAGE_INSTALL actually bakes in at BUILD
# time. Flatpak apps are fetched at RUNTIME (they are not Yocto packages),
# so without this the built image would boot with only a few hundred MB of
# free space and duduclaw-flatpak-kiosk-verify.sh's own disk-safety gate
# would just SKIP the live Chromium fetch every time -- silently defeating
# the point of shipping this verification unit at all. Research spike
# measured Chromium's Flatpak install footprint at 2.4GB; 4GB (KB units,
# OE convention) leaves margin for ostree/flatpak's own working set plus
# the profile directory on top of that. This is a QEMU dev-image-only
# concern -- see the recipe's own header comment for why this entire image
# is scoped to prove the mechanism, not to ship a production kiosk.
IMAGE_ROOTFS_EXTRA_SPACE = "4194304"
