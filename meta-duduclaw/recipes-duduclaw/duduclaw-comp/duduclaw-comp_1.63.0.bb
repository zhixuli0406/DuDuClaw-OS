SUMMARY = "DuDuClaw OS Wayland compositor (Shell-S0 smithay spike)"
DESCRIPTION = "${SUMMARY} -- adapted from smithay's `smallvil` example. \
Source: crates/duduclaw-comp, already a standalone cargo project (its own \
[workspace] empty table, hardcoded version/edition -- created that way from \
day one because smithay is Linux-only and must never touch the macOS \
gateway build's Cargo.lock), snapshotted verbatim by refresh-src.sh."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=87e8e4a396af46e141a08fbc9f1b0455"

# Y2-1 (2026-08-25) status: recipe + crate closure prepared using the same
# proven method as duduclaw-sysd/duduclaw-cli (crate:// per-entry SRC_URI,
# generated from the real Cargo.lock -- see gen-crates-inc.py), but NOT YET
# build-verified -- neither locally (this crate's smithay backend features
# need libinput/libudev/libgbm/libseat/libdrm/libwayland dev headers this
# macOS dev host doesn't have) nor through bitbake (not reached in the Y2-1
# session's remaining time/disk/wall-clock budget -- see the handoff notes).
# DEPENDS below is real, not a guess: every one of these six system
# libraries was individually confirmed present as an oe-core recipe at the
# pinned Yocto 6.0.2 commit (`find meta -iname '<name>*.bb'` inside the
# builder container) -- mesa.bb (no version suffix, easy to miss with a
# glob), libdrm, libinput, wayland, wayland-protocols, libxkbcommon all
# native to oe-core; seatd_0.9.3.bb also provides libseat (the `libseat`
# Rust crate's C library) via its own PACKAGECONFIG[libseat-builtin] split,
# not a separate recipe. No meta-oe layer addition needed for THIS crate,
# unlike what was originally suspected before checking.
#
# Y3-1 (2026-08-26) TWO real gaps found by cross-checking this list against
# crates/duduclaw-comp/BUILD.md's own verified Linux apt dependency list for
# the full udev/DRM backend ("A4-1: udev/DRM backend" section): `apt-get
# install pkg-config libwayland-dev libxkbcommon-dev libinput-dev
# libudev-dev libseat-dev libgbm-dev libdrm-dev`.
#   (1) `libudev-dev` has no equivalent in the DEPENDS list above at all --
#       comp's Cargo.lock pulls `udev`/`input`/`input-sys`/`libudev-sys`
#       (smithay's backend_udev + backend_libinput), all of which need
#       libudev.h/.pc at build time. On oe-core, libudev ships as a
#       PACKAGES_DYNAMIC split OF THE `systemd` RECIPE itself (verified:
#       systemd_259.5.bb's `PACKAGES_DYNAMIC += "^lib(udev|systemd|nss).*"`
#       -- there is no separate standalone `udev`/`eudev` recipe pulled into
#       this build), so the fix is `DEPENDS += "systemd"`, not a
#       udev-named package.
#   (2) `inherit pkgconfig` was entirely missing. Without it, cross-compile
#       PKG_CONFIG_PATH/pkgconfig-native wiring isn't set up the standard OE
#       way, and every one of comp's *-sys build.rs scripts that shells out
#       to `pkg-config` (wayland-sys, xkbcommon-dl, libseat-sys,
#       libudev-sys, gbm-sys, drm-sys) would fail the same way
#       duduclaw-cli_1.62.0.bb's own comment documents openssl-sys failing
#       for the identical reason ("pkg-config command could not be found").
DEPENDS = "wayland wayland-protocols-native libinput seatd libdrm mesa libxkbcommon systemd"

inherit cargo cargo-update-recipe-crates pkgconfig

# See duduclaw-sysd's recipe for why S is UNPACKDIR- not WORKDIR-relative.
SRC_URI = "file://duduclaw-comp-src"
S = "${UNPACKDIR}/duduclaw-comp-src"

require duduclaw-comp-crates.inc

# `debug-affordances` stays OFF (this recipe's default, matching the crate's
# own Cargo.toml default = []) -- Q1's shipping gate (see that feature's own
# doc comment in Cargo.toml) means the built-in stdin human-event simulator
# (Super+Esc emergency stop / Super+Enter resume forgery) must be
# unreachable on a duty machine. No CARGO_BUILD_FLAGS override needed:
# plain `cargo build` already matches this recipe's desired default.
