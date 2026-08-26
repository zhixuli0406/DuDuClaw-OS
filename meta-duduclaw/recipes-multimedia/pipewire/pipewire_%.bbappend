# Y7-3 (2026-08-26) — audio: trim pipewire's default PACKAGECONFIG down to
# what this appliance actually needs, porting the Debian appliance line's D5
# "DELIBERATELY NOT INSTALLED" philosophy (appliance/mkosi.conf's
# pipewire/wireplumber comment block) from apt package selection onto
# meson PACKAGECONFIG, one layer earlier than Debian ever had to reach.
#
# TWO independent problems this file fixes, found by actually reading
# meta-multimedia/recipes-multimedia/pipewire/pipewire_1.6.8.bb, not by
# copying IMAGE_INSTALL and hoping:
#
# (1) A REAL functional gap, not just a size question: pipewire's own
#     PACKAGECONFIG:class-target line gates the SPA ALSA plugin (meson
#     `-Dalsa`, PACKAGECONFIG[alsa] — this is the plugin that opens actual
#     /dev/snd/* hardware, NOT the same thing as PACKAGECONFIG[pipewire-alsa]
#     below) behind `${@bb.utils.filter('DISTRO_FEATURES', 'alsa vulkan
#     pulseaudio', d)}`. This distro's DISTRO_FEATURES (duduclaw-os.conf +
#     init-manager-systemd.inc's auto-appended "systemd usrmerge") is
#     "systemd usrmerge polkit wayland opengl vulkan" — "alsa" is NOT in
#     there. Left at its default, PipeWire would build with its hardware
#     backend plugin DISABLED: no sink would EVER appear, `wpctl status`
#     would show nothing, and every claim in REAL-HW-CHECKLIST.md's audio
#     section would be quietly false despite the package installing cleanly
#     and do_package_qa passing — a silent gap of exactly the shape this
#     project's engineering conventions exist to catch. Fixed by force-
#     enabling PACKAGECONFIG[alsa] here rather than adding "alsa" to global
#     DISTRO_FEATURES (narrower blast radius — this appliance has no other
#     ALSA-aware recipe whose behaviour should change).
#
# (2) Footprint: left otherwise at its own unconditional defaults, this
#     recipe's PACKAGECONFIG:class-target also unconditionally pulls in
#     avahi, the full bluez5 codec stack, flatpak, gstreamer1.0 (+
#     gstreamer1.0-plugins-base), jack, libcamera (+libdrm), libusb,
#     raop (openssl-based AirPlay receiver), sndfile, v4l2, and
#     webrtc-audio-processing-2 — none of which this appliance's kiosk
#     shell (crates/duduclaw-shell/src/audio/wpctl.rs, a plain `wpctl`
#     subprocess driver) or wireplumber's own default policy scripts need.
#     Debian's D5 round could only trim at the .deb package-selection
#     level (pipewire-audio/-pulse/-alsa/libspa-0.2-bluetooth left
#     uninstalled); building from source here means trimming one level
#     earlier, at the meson flags themselves, which additionally saves the
#     BUILD-time cost of compiling gstreamer/libcamera/webrtc-audio-
#     processing support that would then just sit on disk unused — real
#     savings on a build host already flagged as disk-constrained (see
#     meta-duduclaw/README.md "磁碟策略").
#
# Explicitly KEPT, each for a reason mirroring D5's own audio-stack
# reasoning:
#   alsa      — see (1) above: the actual hardware backend. NOT the same as
#               `pipewire-alsa` below.
#   udev      — device hot-plug detection; the ALSA SPA plugin's monitor
#               needs this to notice a sound card appearing/disappearing at
#               all, not just to open one already known at startup.
#   volume    — softvolume/channel-volume support; zero extra DEPENDS, and
#               `wpctl set-volume` / the shell's slider are meaningless
#               without it.
#   systemd, systemd-system-service, systemd-user-service — build/install
#               pipewire's own unit files (libsystemd link for journald
#               logging too). Mirrors Debian's shipped package contents:
#               the unit files EXIST but are never systemctl-enabled here
#               either — duduclaw-kiosk-launch.sh starts the daemon by hand,
#               same "no logind session, no systemd --user" reasoning D5
#               already documented (this image's kiosk unit has no PAM
#               session either — see duduclaw-kiosk.service's own header).
#   wireplumber — RDEPENDS wiring onto the wireplumber package (this
#               recipe's own PIPEWIRE_SESSION_MANAGER default), matching
#               D5's explicit choice of wireplumber over pipewire-media-
#               session.
#   pw-cat    — ships `pw-play`/`pw-cat`/`pw-record`, the only realistic way
#               to actually push a test tone through a real device on THIS
#               image: alsa-utils (`speaker-test`, which REAL-HW-CHECKLIST.md
#               §6 mentions as a Debian-line-style fallback) is not installed
#               here at all, and D5's own Debian-line verification used
#               exactly this class of tool.
#   sndfile   — Y7-1 (2026-08-26) real do_configure failure, hit by actually
#               running bitbake: "pw-cat is enabled but required dependency
#               `sndfile` was not found" (../sources/pipewire-1.6.8/src/
#               tools/meson.build's pw-cat target hard-requires it whenever
#               pw-cat itself is enabled -- this recipe's own comment above
#               claiming pw-cat needs "zero extra DEPENDS beyond alsa" was
#               the one claim in this file not actually true against
#               pipewire's real meson.build). PACKAGECONFIG[sndfile] (the
#               upstream recipe's own option, `-Dsndfile=enabled/disabled,
#               libsndfile1`) already exists and libsndfile1 is a plain
#               oe-core recipe (recipes-multimedia/libsndfile/) -- adding it
#               here is the direct, uncontroversial fix for pw-cat's actual
#               requirement, not a new feature decision.
#
# Explicitly DROPPED (each one Debian's D5 comment already ruled out for the
# identical reason, just re-derived at the meson-flag level instead of the
# apt-package level):
#   pipewire-alsa   — legacy-ALSA-app redirect shim. No ALSA app on this
#                     appliance; the shell speaks wpctl directly.
#   pulseaudio      — no libpulse-speaking app here either (and DISTRO_
#                     FEATURES has no "pulseaudio" token to gate it on
#                     anyway).
#   bluez / bluez-* — no BT stack in this image (no `bluez5` recipe pulled
#                     in), so the plugin would bind to nothing, same as
#                     D5's libspa-0.2-bluetooth exclusion.
#   avahi, flatpak, gstreamer, jack, libcamera, libcanberra, raop, readline,
#   ncurses, sdl2, v4l2, webrtc-echo-cancelling, docs, ffmpeg, media-session
#                   — no consumer on this appliance for any of them; see (2)
#                     above.
#
# `:class-target` matches the base recipe's own override scope (it uses
# `PACKAGECONFIG:class-target ??=`, i.e. native/nativesdk builds are
# untouched by this file either way).
PACKAGECONFIG:class-target = "alsa udev volume systemd systemd-system-service systemd-user-service wireplumber pw-cat sndfile"
