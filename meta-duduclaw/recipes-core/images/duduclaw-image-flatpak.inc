# DuDuClaw OS — Flatpak/Steam/Chromium app-carriage payload (Y14-A, 2026-08-27).
#
# Extracted verbatim from duduclaw-image-flatpak.bb's own IMAGE_INSTALL:append
# block + IMAGE_ROOTFS_EXTRA_SPACE (Y3-2..Y6-3, unchanged since) so it can be
# shared by BOTH the /data-based single-root flatpak line
# (duduclaw-image-flatpak.bb, ESP+root+data) and the A/B line
# (duduclaw-image-appliance.bb, ESP+root-A+root-B+data) without one
# `require`-ing the other's `.bb` — see
# commercial/docs/DESIGN-image-convergence-2026-08.md §2.2: this is a plain
# `IMAGE_INSTALL`/`IMAGE_ROOTFS_EXTRA_SPACE` data file, no `inherit`/
# `WKS_FILE`, so it carries no partition-layout assumption at all and is
# safe to `require` from either partflags branch.
#
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
# choosers, screen share) actually needs it -- not blocking this
# milestone's own scope (kiosk mechanism + OS permission foundation).
#
# duduclaw-polkit-flatpak: this layer's own OS-side permission rule (item 4
# of the Y3-2 ticket) -- see that recipe for the full reasoning on why it
# does not just reuse flatpak's stock wheel-group rule unchanged.
#
# duduclaw-steam-devices (Y5-2): host-side udev rule Steam's Flatpak
# wrapper's check_device_perms() actually requires (/dev/uinput
# group=input) -- see that recipe for the full one-hand-verified reasoning.
#
# duduclaw-flatpak-offline-repo (Y6-3): bakes a pre-normalized 2.4G
# OSTree/Flatpak repo (Chromium + its 7 runtime/extension deps) into
# /opt/duduclaw-flatpak-offline-repo at IMAGE BUILD time, so a real machine
# with zero network at first boot still has a working Chromium kiosk
# fallback -- see that recipe's own header for why this exists (the
# official sideload-repos mechanism does not work, confirmed on two
# separate flatpak versions) and duduclaw-flatpak-kiosk-verify.sh's
# "Offline preload repo" section for the consumer side.
IMAGE_INSTALL:append = " \
    dbus \
    flatpak \
    bubblewrap \
    ostree \
    duduclaw-polkit-flatpak \
    duduclaw-flatpak-kiosk-verify \
    duduclaw-steam-devices \
    duduclaw-flatpak-offline-repo \
"

# --- Disk headroom on top of the baked-in offline repo --------------------
# wic's efi-uki-bootdisk.wks.in has no fixed --size on the root partition
# (`part / --source rootfs ...`) -- it auto-sizes off IMAGE_ROOTFS_SIZE,
# which is computed from what IMAGE_INSTALL actually bakes in at BUILD
# time. Y6-3 update: duduclaw-flatpak-offline-repo (added above) now bakes
# ~2.4G of the Chromium/runtime OSTree content in as an ordinary package,
# so that specific weight IS already counted by IMAGE_ROOTFS_SIZE's normal
# auto-sizing -- this EXTRA_SPACE margin is no longer "the whole Chromium
# download has zero build-time footprint" (that was the Y3-2-era
# rationale, now stale) but headroom for: (a) `flatpak install`'s own
# checkout of the offline repo into the named installation's app/ tree --
# expected to mostly hardlink against the repo's own objects since both
# live on the same rootfs, but not zero; (b) ostree/flatpak's tmp/staging
# working set; (c) the profile directory Chromium writes into at runtime;
# (d) the LIVE network flathub path (duduclaw-flatpak-kiosk-verify.sh
# still falls back to it if the offline repo is absent/broken) still needs
# room for a fresh 2.4G download on top of whatever's already on disk.
# Kept at the same 4GB (KB units, OE convention) rather than tuned down,
# since (a)+(d) together could plausibly approach it and this is a
# disk-safety margin, not a tightly-budgeted allocation.
#
# On duduclaw-image-appliance.bb this margin applies to root-A's
# AUTO-sizing input ONLY in the sense that IMAGE_ROOTFS_SIZE still folds it
# in when wic decides how much headroom the populated rootfs directory
# itself wants -- but the A/B wks's root-A/root-B partitions are
# `--fixed-size ${DUDUCLAW_AB_SLOT_SIZE_MB}`, NOT auto-sized off
# IMAGE_ROOTFS_SIZE, so this variable's practical effect there is bounded
# by do_rootfs's own free-space check (do_image_wic fails outright if the
# populated rootfs directory does not fit inside the fixed slot size) —
# it is not silently ignored, but it no longer directly drives the final
# partition size the way it does on the single-root data/flatpak line.
IMAGE_ROOTFS_EXTRA_SPACE = "4194304"
