# DuDuClaw OS — app-compat payload (CP-1, 2026-08-30).
#
# Shared IMAGE_INSTALL set for the app-compatibility layer
# (commercial/docs/DESIGN-app-compat-layer-2026-08.md; wave plan
# TODO-compat-cp1-2026-08.md). Same "pure IMAGE_INSTALL data file, no
# inherit/require of its own" shape as duduclaw-image-desktop.inc /
# duduclaw-image-flatpak.inc — see the former's header for why these
# payload sets live in .inc files the image recipes `require` instead of
# being pasted per-recipe.
#
# duduclaw-compat-runners: the compat.d declaration files (bottles.toml /
#   waydroid.toml) + the discovery dirs. Config-only; the scanner itself
#   lives in the duduclaw binary (`duduclaw compat list`,
#   duduclaw-core::compat_runners). Ships even where a runner's own
#   payload is absent ON PURPOSE — a declared-but-missing runner is the
#   honest `missing: <tool>` state the CP-1 acceptance criterion exercises,
#   not an error.
#
# waydroid: Android app runner (design §2.4). Pulls the whole packaging
#   chain (lxc, libgbinder, python3-gbinder, dnsmasq, iptables, gtk+3,
#   python3-pygobject, pipewire-pulse — the last one exists only because
#   pipewire_%.bbappend re-enabled the `pulseaudio` PACKAGECONFIG, see that
#   file's CP-1 comment) transitively via its own RDEPENDS. Kernel-side
#   binder support is recipes-kernel/linux-yocto/duduclaw-binder.cfg.
#   DELIBERATELY NOT SHIPPED: GApps, ARM translation (libhoudini/libndk) —
#   design §2.4's legal red line; the user-facing self-install entry is
#   docs/guides/app-compat.md. `waydroid init` downloads the Android
#   system image at runtime onto /data — nothing Android lands in this
#   rootfs.
#
# Bottles (windows-app runner) is intentionally NOT an IMAGE_INSTALL here:
# design §2.3 ships it via the Flathub channel (network install), so its
# only image-side artifact is the compat.d declaration above. Xwayland —
# its display prerequisite — rides duduclaw-image-desktop.inc (compositor
# companion, not app payload).

IMAGE_INSTALL:append = " duduclaw-compat-runners waydroid"
