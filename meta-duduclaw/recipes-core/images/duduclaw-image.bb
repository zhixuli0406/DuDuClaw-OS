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

# --- Chinese input method: fcitx5 + fcitx5-chewing (Y6-1, 2026-08-26) ----
# Three self-authored recipes (recipes-support/{extra-cmake-modules,
# libchewing,fcitx5,fcitx5-chewing}/ -- see each recipe's own header for
# the availability research proving none of this exists anywhere in the OE
# ecosystem) porting the Debian appliance line's D3/D3-f/W7-3 Chinese-input
# work onto this base. `dbus` is listed explicitly even though systemd/
# other components likely already pull it transitively -- the Yocto-side
# duduclaw-kiosk-launch.sh (duduclaw-shell recipe) now starts a D-Bus
# SESSION bus itself (mirroring the Debian line's `dbus-run-session`
# wrapper, a gap this image's kiosk launch script previously documented as
# an explicit Y3-1 deferral -- "no ... D-Bus-session-bus ... wiring") for
# fcitx5 to register on; an explicit DEPENDS here makes that dependency
# non-implicit rather than hoping some other component's transitive pull
# never goes away.
#
# RE-ENABLED (Y7-1, 2026-08-26). Y6-3 had temporarily commented the two IME
# packages out (see git history of this file for that note) after hitting
# `fcitx5_5.1.12.bb:do_compile`'s `fmt::localtime()` removal — that was
# ALREADY fixed by Y6-1's own patch 0001 before Y6-3 even hit it (Y6-3's
# build ran concurrently against a stale checkout); the actual blocker Y7-1
# found and fixed was two unrelated, LATER-stage `do_package_qa` failures
# (buildpaths leak in fcitx5's own CMakeLists.txt `get_filename_component`
# call + a cross-compile sysroot leak in its bundled FindIsoCodes.cmake —
# see fcitx5_5.1.12.bb's own EXTRA_OECMAKE/patch comments — plus two missing
# FILES entries on fcitx5-chewing). Both recipes now `bitbake` clean start
# to finish (do_package_qa PASS, RPMs produced) — verified live, not
# assumed from reading the fix alone.
IMAGE_INSTALL:append = " dbus fcitx5 fcitx5-chewing"

# --- Network: Wi-Fi via iwd + systemd-networkd (Y7-3, 2026-08-26) ---------
# Closes REAL-HW-CHECKLIST.md §5's honest gap: this image previously had
# firmware blobs (Y2-2's linux-firmware-iwlwifi/-mediatek/-rtl-nic, machine
# .conf) and kernel drivers (Y2-2's duduclaw-{n305,8845hs}.cfg fragments)
# but NO userspace connection-management stack at all -- a Wi-Fi-capable
# kernel with nothing able to actually join a network. Ports the Debian
# appliance line's D4a-1 decision (DESIGN-network-settings-2026-08.md §2,
# decision A-①: iwd + systemd-networkd over NetworkManager + wpa_supplicant,
# measured there at 12.6x less resident memory and 2 packages vs 12) onto
# this Yocto image -- `iwd` resolves from meta-oe (recipes-connectivity/
# iwd/iwd_3.12.bb, one-hand-verified present at the pinned meta-openembedded
# commit, see kas/duduclaw-os.yml), no new layer needed for it.
#
# duduclaw-network-config (this layer's own small recipe, recipes-
# connectivity/duduclaw-network-config/) carries the matching
# 25-wireless-dhcp.network drop-in and RDEPENDS on iwd +
# wireless-regdb-static -- see that recipe's own header for why
# `wireless-regdb-static`, not bare `wireless-regdb`, is the package this
# kernel actually needs (an OE package split with no Debian equivalent).
#
# gateway's D-Bus client for iwd (crates/duduclaw-gateway/src/network/
# iwd.rs, from the Debian line's D4a-3) needs ZERO Yocto-side changes --
# confirmed byte-identical between crates/ and this recipe's own vendored
# duduclaw-cli-src/ snapshot before this ticket touched anything, so the
# same binary that already speaks iwd's D-Bus API on the Debian line speaks
# it here too, the moment iwd itself is actually on the image.
#
# NO netdev group / SupplementaryGroups wiring, and this is a REAL
# divergence from the Debian line's D4a-1, not an oversight: the Debian
# line needed `netdev` because ITS gateway runs as an unprivileged
# `duduclaw` service user (appliance/mkosi.extra's gateway unit, `User=
# duduclaw`) and iwd's D-Bus policy denies everyone except root/sudo/netdev
# by default. THIS image's duduclaw-gateway.service (duduclaw-cli's own
# recipe, files/duduclaw-gateway.service) has no `User=` line at all -- it
# runs as root, per this Yocto product line's own Y2-1 bring-up decision
# ("this Yocto image doesn't provision a non-root service user ... yet").
# Root already clears any sane default-deny D-Bus policy's root/sudo hole
# with no group membership needed, so the whole netdev mechanism the Debian
# line built is currently a no-op HERE. NOT independently verified against
# the exact D-Bus policy file iwd's upstream tarball installs (unlike the
# Debian line's own iwd .deb, which is confirmed to patch in a `netdev`
# policy stanza) -- flagged rather than assumed, and this comment is the
# marker to revisit the moment this Yocto line's gateway ever moves to an
# unprivileged service user (matching the Debian line's own architecture),
# at which point the D4a-1 netdev machinery needs porting for real.
#
# Firmware is NOT repeated here -- already on the machine (duduclaw-
# genericx86-64.conf's MACHINE_EXTRA_RRECOMMENDS, Y2-2) and does not need a
# duduclaw-qemux86-64 equivalent (QEMU has no real Wi-Fi radio to load
# firmware for at all; this ticket's own QEMU verification is therefore
# necessarily limited to "iwd daemon runs + D-Bus service registers +
# gateway's iwd.rs gets a real, non-error 'no adapter' answer instead of
# erroring out", NOT "a real network associates" -- that half needs the
# real N305/8845HS hardware, same honest limit REAL-HW-CHECKLIST.md already
# states for the Debian line's own equivalent).
IMAGE_INSTALL:append = " iwd wireless-regdb-static duduclaw-network-config"

# --- Audio: PipeWire + WirePlumber (Y7-3, 2026-08-26) ---------------------
# Closes REAL-HW-CHECKLIST.md §6's honest gap: duduclaw-shell already ships
# a real wpctl-subprocess audio backend (crates/duduclaw-shell/src/audio/
# wpctl.rs, confirmed byte-identical in this recipe's own vendored
# duduclaw-shell-src/ snapshot before this ticket touched anything) and a
# real settings-page UI, but neither `pipewire` nor `wireplumber` was ever
# in this image's IMAGE_INSTALL -- `wpctl` almost certainly did not exist on
# any Yocto image built to date, same diagnosis the Debian line's D5 round
# made before it existed there either.
#
# `pipewire`/`wireplumber` resolve from meta-multimedia, a DIFFERENT
# meta-openembedded sublayer than meta-oe -- added to kas/duduclaw-os.yml
# for this ticket (that file's own comment has the full LAYERDEPENDS/
# LAYERSERIES_COMPAT verification, including why meta-python comes along
# for the ride). A `pipewire_%.bbappend` (recipes-multimedia/pipewire/, this
# ticket) force-enables the SPA ALSA hardware backend PACKAGECONFIG that
# would otherwise silently build DISABLED on this distro (DISTRO_FEATURES
# has no "alsa" token) and trims the rest of pipewire's own unconditional
# defaults (gstreamer/libcamera/jack/avahi/webrtc-echo-cancelling/raop/...)
# down to the same "wpctl-only, no ALSA-app shim, no PulseAudio shim, no
# Bluetooth" shape the Debian line's D5 round chose at the apt-package
# level -- see that bbappend's own header for the full accounting.
#
# Session wiring (kiosk user's `audio` group + the kiosk-launch.sh
# start_audio_session function that hand-starts both daemons before any
# compositor) lives in duduclaw-shell's own recipe/files, ported from D5's
# exact reasoning: this kiosk is a plain systemd SYSTEM service with no
# logind session, so there is no `systemd --user` manager to activate
# pipewire.service/wireplumber.service the way Debian ships them -- see
# duduclaw-kiosk-launch.sh's own comment block for the full port.
#
# QEMU verification note (this ticket): qemux86-64's default machine has no
# emulated sound device at all unless one is added to the runqemu/QEMU
# invocation -- appliance/run-vm-yocto.sh (this line's own QEMU launcher)
# gained `-audiodev none -device intel-hda -device hda-duplex` for this
# ticket, mirroring the Debian line's own run-vm.sh `-audiodev`/intel-hda
# convention (REAL-HW-CHECKLIST.md §6 already names this as the expected
# QEMU device shape) -- without it `wpctl status` would correctly show zero
# sinks even with a fully working PipeWire/WirePlumber, which would be
# indistinguishable from the packages being silently disabled the way (1)
# above almost let happen for Wi-Fi's ALSA plugin.
IMAGE_INSTALL:append = " pipewire wireplumber"

# --- kernel-modules umbrella (Y7-3, 2026-08-26 QEMU verification fix) ----
# Real bug caught by actually booting the image in QEMU, not by re-reading
# the recipe: both the network and audio work above LOOKED complete
# (bitbake succeeded, `which wpctl pipewire wireplumber` all resolved, iwd's
# binary was on the image) but on first boot `systemctl is-active iwd`
# reported `failed` and `/proc/asound/cards` was empty with `lsmod | grep
# snd` returning nothing at all. Root cause, same SHAPE in both cases: the
# kernel .config already has everything needed built as a MODULE
# (`CONFIG_CRYPTO_USER_API_HASH=m` / `CONFIG_CRYPTO_USER_API_SKCIPHER=m` for
# iwd's AF_ALG crypto backend; `CONFIG_SND_HDA_INTEL=m` +
# `CONFIG_SND_HDA_CODEC_*=m` for the audio controller), and linux-yocto's
# module-splitting machinery DOES build+package every one of them
# individually (`kernel-module-algif-hash`, `kernel-module-algif-skcipher`,
# `kernel-module-snd-hda-intel`, `kernel-module-snd-hda-codec-realtek`, ...
# — confirmed present as real .rpm files in this exact build's own deploy/
# rpm/ output) — but NONE of those package names were ever referenced
# anywhere in this image's IMAGE_INSTALL or in iwd's own RRECOMMENDS
# (iwd_3.12.bb's RRECOMMENDS:${PN} only lists the PKCS7/PKCS8/X509
# key-parser modules needed for EAP-TLS certificates — it does NOT
# RRECOMMEND the AF_ALG glue modules its own crypto backend needs, an
# upstream/OE recipe gap, not a Yocto-line mistake), so `modprobe`d up
# built .ko files simply never made it onto the rootfs at all. Live-verified
# the exact failure mode too: `modprobe algif_hash` on the booted VM failed
# with "FATAL: Module algif_hash not found in directory
# /lib/modules/6.18.24-yocto-standard" — the module truly is not there, not
# just unloaded.
#
# Fix: `kernel-modules`, the standard oe-core umbrella meta-package that
# RDEPENDS on every kernel-module-* package this exact kernel build
# produced (kernel.bbclass's own module-split mechanism, not hand-picked by
# this recipe). Deliberately NOT hand-listing `kernel-module-algif-hash
# kernel-module-algif-skcipher kernel-module-snd-hda-intel
# kernel-module-snd-hda-codec-realtek ...` individually: this image doesn't
# yet know which exact HDA codec chip the real N305/8845HS hardware carries
# (REAL-HW-CHECKLIST.md's own "AX-series module TBD" disclosure for Wi-Fi
# firmware applies here too, for the audio codec), and enumerating "the
# codecs QEMU's intel-hda emulates" would silently under-cover real
# hardware the same way the original bug under-covered everything. The
# umbrella costs disk (every built module, not just the ones this ticket
# needed) but removes the guessing entirely — same trade-off direction this
# project already made for MACHINE_EXTRA_RRECOMMENDS's firmware subset
# (explicit, not narrowed to a guess), just resolved the other way here
# because unlike firmware there is no per-chip package split cheap enough
# to enumerate confidently without the real hardware in hand.
IMAGE_INSTALL:append = " kernel-modules"

# --- Entry B: 實體救援開機項 (Y7-2, 2026-08-26) ---------------------------
# Authority: commercial/docs/DESIGN-maintenance-mode-2026-08.md §3 — the
# Yocto-line-specific rescue boot entry, dependent on the sd-boot menu
# mechanism (DRAFT-no-linux-surface-2026-08.md item 4) which this ticket
# also realizes on this line for the first time (no loader.conf existed
# on this line before this ticket at all — wic's own auto-generated
# default was silently in effect, see duduclaw-rescue-boot.bbclass's own
# header for the exact finding).
#
# `duduclaw-rescue-boot` (meta-duduclaw/classes/) is the MECHANISM: builds
# a second signed UKI (same kernel+initramfs as the product UKI, cmdline
# `systemd.unit=duduclaw-rescue.target`) and overrides wic's own
# auto-generated loader.conf with a hardened one (`timeout 0` + `editor
# no` — the `editor no` line is a real gap this ticket found and closed,
# see that class's own comment and the fetched loader.conf file's header
# for the systemd upstream documentation evidence).
#
# `duduclaw-rescue` (recipes-duduclaw/duduclaw-rescue/) is the POLICY: the
# target itself, its diagnostic-shell/audit/root-lock units, the
# restricted non-root autologin account, and the emergency.target/
# rescue.target mask — see that recipe's own header for the full
# identity-model decision record (§3.3 option (a) chosen over (b)) and the
# DRAFT item 5 (emergency.target) mask decision.
inherit duduclaw-rescue-boot

# Y7-1 (2026-08-26) real parse-time fix, hit while rebuilding
# duduclaw-image-flatpak (this ticket's own deliverable, which `require`s
# this file): "Unable to get checksum for duduclaw-image-flatpak SRC_URI
# entry duduclaw-loader.conf: file could not be found" -- bitbake's default
# FILESPATH is computed from the OUTERMOST recipe's PN/BPN (whichever .bb
# file bitbake was actually asked to build), not the PN of whichever file a
# `require`d snippet happens to live in; Y7-2's own `bitbake duduclaw-image`
# runs never hit this because there PN really is `duduclaw-image` and the
# default `${THISDIR}/duduclaw-image/` search entry already covers it --
# only a *different* top-level recipe requiring this one (duduclaw-image-
# flatpak.bb) exposes the gap. Explicit FILESEXTRAPATHS makes the lookup
# PN-independent, matching the fix's own file (still `duduclaw-image/
# duduclaw-loader.conf`, untouched -- this only adds a search path, it does
# not move/rename Y7-2's file).
FILESEXTRAPATHS:prepend := "${THISDIR}/duduclaw-image:"

SRC_URI += "file://duduclaw-loader.conf"

IMAGE_INSTALL:append = " duduclaw-rescue"
