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

# --- "開機即殼" (Y3-1, 2026-08-25) -------------------------------------
# duduclaw-comp (compositor) + duduclaw-shell (its client, which also
# carries duduclaw-kiosk.service/duduclaw-kiosk-launch.sh -- see that
# recipe's own comment for why the systemd unit lives there and not on
# duduclaw-comp: comp is a plain subprocess of the kiosk launch script, not
# an independently systemd-managed unit, matching the Debian appliance
# line's `run_comp_session` shape).
#
# mesa-megadriver / mesa-vulkan-drivers are explicit, not left to automatic
# shlib RDEPENDS resolution: comp/shell link against libgbm.so/
# libvulkan.so (caught by the normal ELF NEEDED-based auto-RDEPENDS
# mechanism), but the actual GPU/software-rendering backend drivers
# (llvmpipe, virtio_gpu, the vulkan gfxstream ICD) are dlopen()'d at
# runtime, not linked -- invisible to that mechanism entirely. mesa.inc
# does RRECOMMENDS mesa-megadriver from libgl-mesa/libegl-mesa
# automatically (verified: meta/recipes-graphics/mesa/mesa.inc's
# `d.appendVar("RRECOMMENDS:" + fullp, " ${MLPREFIX}mesa-megadriver" +
# suffix)`), which would likely pull it in anyway, but this is listed
# explicitly rather than depended on implicitly for the same reason this
# repo's other image recipes prefer explicit installs over relying on
# RRECOMMENDS being honored.
#
# Y3-8 (2026-08-26) real boot failure fix: the ORIGINAL version of this
# comment (above) claimed libEGL.so was linked/auto-RDEPENDS-covered like
# libgbm/libvulkan -- that claim was WRONG, caught by a live QEMU boot
# actually panicking, not by re-reading the recipe:
#   thread 'main' panicked at .../smithay-0.7.0/src/backend/egl/ffi.rs:148
#   Failed to load LibEGL: DlOpen { desc: "libEGL.so.1: cannot open shared
#   object file: No such file or directory" }
# The word "DlOpen" in smithay's own error is the tell: smithay's EGL
# backend dynamically dlopen()s libEGL.so.1 (via the same `libloading`-style
# pattern the mesa GPU driver .so's already use), it does NOT link it as an
# ELF NEEDED entry -- so it is exactly as invisible to auto-RDEPENDS as
# mesa-megadriver/mesa-vulkan-drivers already are, just missed when this
# image recipe was first written. comp panicking kills its Wayland socket,
# which makes duduclaw-shell's own client connection see "Connection reset
# by peer" and panic too, which makes duduclaw-kiosk-launch.sh exit 101,
# which duduclaw-kiosk.service's Restart=always retries every 5s until
# StartLimitBurst=8 within StartLimitIntervalSec=300 is hit and systemd
# gives up ("Start request repeated too quickly", "Failed to start DuDuClaw
# kiosk session") -- confirmed via `systemctl show -p NRestarts` climbing
# 1->6+ across repeated checks on a live boot, not inferred from the panic
# alone. `libegl-mesa` (verified package name+contents:
# `meta/recipes-graphics/mesa/mesa.inc`'s `FILES:libegl-mesa =
# "${libdir}/libEGL*.so.* ${datadir}/glvnd/egl_vendor.d"`) is the fix.
#
# xkeyboard-config is added explicitly too: libxkbcommon (comp/shell's
# keymap compiler, DEPENDS'd at build time by both recipes) needs the
# actual XKB rules/layouts data files under ${datadir}/X11/xkb at RUNTIME
# to compile any keymap at all -- without this package the library itself
# is present and links fine, but every keyboard event fails to resolve to
# a keysym (confirmed present as its own oe-core recipe,
# recipes-graphics/xorg-lib/xkeyboard-config_2.47.bb -- not a guessed
# package name).
#
# Y5-4 (2026-08-26) real boot failure fix, same class of bug as the Y3-8
# libEGL fix above -- caught live on a Yocto VM boot, not by re-reading the
# recipe: duduclaw-shell panicked cleanly (exit 101, "SingleFullscreen
# fallback must always be able to open a plain toplevel window: No GPU
# adapter found that can configure the display surface") because gpui's
# Linux renderer (`blade`, via the `ash` crate) is Vulkan-only per
# duduclaw-shell's own BUILD-LINUX.md ("gpui's blade renderer needs a
# Vulkan device; cage's own GL stack is not enough") and `libvulkan.so.1`
# -- the actual Khronos Vulkan LOADER, not any of the per-vendor ICD driver
# .so's -- was entirely absent from the image. `mesa-vulkan-drivers`
# (already listed above) only ships `libvulkan_*.so` (the ICD backends,
# including lavapipe's `libvulkan_lvp.so`) and the `icd.d/*.json`
# manifests the loader reads to find them (verified against
# openembedded-core/meta/recipes-graphics/mesa/mesa.inc's own
# `FILES:mesa-vulkan-drivers` line) -- the loader itself is a separate
# recipe (`recipes-graphics/vulkan/vulkan-loader_*.bb`) that mesa.inc only
# pulls in as a build-time DEPENDS (`PACKAGECONFIG[vulkan]`), never as a
# runtime RDEPENDS of `mesa-vulkan-drivers`. And because `ash`-based Rust
# Vulkan code typically dlopens libvulkan.so.1 at runtime rather than
# carrying an ELF NEEDED entry for it, this is invisible to automatic
# shlib RDEPENDS resolution the same way libEGL.so.1 was -- confirmed live
# by extracting the already-built `vulkan-loader` artifact out of this same
# build's own sysroot-components and hand-installing it into a running VM,
# after which duduclaw-shell got past the "no adapter" panic entirely and
# started actually initializing lavapipe. `vulkan-loader` is the fix.
IMAGE_INSTALL:append = " duduclaw-comp duduclaw-shell mesa-megadriver mesa-vulkan-drivers vulkan-loader libegl-mesa xkeyboard-config"
