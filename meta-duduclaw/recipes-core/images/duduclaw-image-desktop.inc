# Shared "desktop stack" IMAGE_INSTALL set — duduclaw-comp/duduclaw-shell
# (the compositor + its GPU/keyboard runtime deps), the fcitx5 Chinese IME,
# PipeWire/WirePlumber audio, the kernel-modules umbrella, and (Y20-P4) the
# Japanese CJK fallback font every gpui surface needs. `require`d by BOTH
# `duduclaw-image.bb` (the production OOBE/appliance line) and
# `duduclaw-image-live.bb` (the throwaway live-installer environment) —
# every one of these five concerns is needed by the exact same
# `duduclaw-shell`/`duduclaw-comp` binaries running the exact same kiosk
# shape on either side, just under a different systemd unit owner (kiosk
# user vs. root — see `duduclaw-live-tweaks.bb`'s own header).
#
# ── Y20-P4 (2026-08-29): why this file exists now, not earlier ────────────
# `duduclaw-image-live.bb`'s own Y20-P1 header (git blame that file for the
# original wording) COPIED these same five `IMAGE_INSTALL:append` lines
# byte-for-byte from `duduclaw-image.bb` rather than sharing them, and said
# so explicitly: "extracting a shared duduclaw-image-desktop.inc now would
# put this throwaway spike recipe in the same edit blast radius as the
# production image line before P1 has even proven the desktop stack works
# here at all... deferred to P4". P1/P2/P3 have since each independently
# proven the live desktop stack boots, renders the graphical installer
# wizard, and drives a real disk write — the deferral's own precondition is
# satisfied, so this ticket does the extraction the P1 comment always
# intended.
#
# ── Verified NOT to change what either image actually installs ───────────
# This is a pure move, not a behavior change: every line below is
# byte-identical to what `duduclaw-image.bb` and `duduclaw-image-live.bb`
# already carried independently (the Y20-P4 Japanese-font line is the one
# exception — see its own comment below for why folding it in here, rather
# than duplicating it a second time across both callers, is the right
# scope for this same ticket). Checked with `bitbake -e duduclaw-image` /
# `bitbake -e duduclaw-image-appliance` / `bitbake -e duduclaw-image-live`
# before and after this extraction: the resulting `IMAGE_INSTALL` value is
# the same SET of packages for all three (string order shifts, because
# `require`'s expansion point necessarily collapses what used to be four
# separately-positioned append statements into one contiguous block — see
# this ticket's own handoff notes for the full before/after diff — but
# bitbake's package-manager backends consume `IMAGE_INSTALL` as an
# unordered set, not a sequence, so this has no runtime effect).

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

# --- Japanese CJK glyphs for OOBE/installer (Y20-P4, 2026-08-29) ---------
# Real visual defect, caught on Y19's own live-installer QEMU screenshot and
# tracked since as a known-but-deferred P4 item (commercial/docs/
# TODO-agent-first-os-2026-08.md Y19 row; DESIGN-graphical-installer-
# 2026-08.md's own P3 "known issues" list): the OOBE/installer language
# picker's Japanese subtitle ("言語を選択" / "この設定はあとから変更でき
# ます") rendered "択"/"変" as missing-glyph bars. Root cause traced to
# `duduclaw-native-gui/src/theme.rs`'s own `app_font()`/`BUNDLED_FONTS` doc
# comments: this crate bundles ONLY "Inter Variable" + "Noto Sans TC" (a
# Traditional-Chinese-only subset) and registers a single CJK fallback
# family with gpui's text system — those two Japanese-specific kanji simply
# are not in the TC charset. gpui's Linux text system (`font-kit`; both
# `duduclaw-shell` and `duduclaw-comp` already DEPENDS on `fontconfig` at
# build time) has a SECOND fallback tier below the bundled families — the
# system's own fontconfig-registered fonts — but until now neither image
# ever installed any, so that tier had nothing to find. `source-han-sans-
# jp-fonts` (Adobe/Google's Pan-CJK family, Japanese subset; already
# vendored in this kas config's own `meta-openembedded/meta-oe` layer at
# `recipes-graphics/ttf-fonts/source-han-sans-jp-fonts_2.004.bb` — no new
# recipe needed) is exactly that missing system font: it installs its own
# `/etc/fonts/conf.d/44-source-han-sans-jp-fonts.conf` and `inherit
# fontcache` auto-appends a `fontconfig-utils` RDEPENDS (openembedded-
# core's own `fontcache.bbclass`, `FONT_EXTRA_RDEPENDS`) — which itself
# auto-RDEPENDS on `fontconfig` (the shlib package) via the ordinary
# shlib-provider mechanism, since `fc-cache` links `libfontconfig.so.1` —
# so this ONE line is fully self-contained: no separate `fontconfig`/
# `fontconfig-utils` IMAGE_INSTALL entry and no hand-authored fontconfig
# conf needed on top of it.
#
# Lives HERE (in the shared .inc), not duplicated once per caller the way
# the other four blocks in this file historically were before this same
# ticket deduped them: both `duduclaw-image.bb`'s production OOBE and
# `duduclaw-image-live.bb`'s installer wizard hit the identical two glyphs
# through the identical `duduclaw-native-gui` font stack, so unlike the
# other four blocks (which predate this .inc and are being moved verbatim)
# this one was authored directly at its final, de-duplicated home.
IMAGE_INSTALL:append = " source-han-sans-jp-fonts"

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
