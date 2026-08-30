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
#
# --- CP-2 wave-1/B2 (2026-08-30) — windows-vm runner base -------------------
# commercial/docs/DESIGN-app-compat-layer-2026-08.md §2.3 path B: a
# self-contained dockur/windows container (Windows install image fetched by
# the container on first run, nothing Windows lands in this rootfs — same
# "declare the runner, download the payload at use-time" shape as waydroid
# above) driven through FreeRDP's RemoteApp seamless-window mode. Not
# Flatpak-packaged — WinBoat's own Flatpak build hit real sandbox/USB/GPU
# passthrough issues the design doc's research cites; this path installs
# the upstream-packaged binaries directly, same as every other runner in
# this file. TODO-compat-cp2-2026-08.md B2 is the wave that added these
# four packages; B3 (separate ticket) adds the `duduclaw compat windows-vm`
# CLI + its own compat.d declaration (windows-vm.toml, not touched here).
#
# docker (meta-virtualization/recipes-containers/docker, docker-moby_git.bb
#   at the time of writing): the container runtime dockur/windows runs
#   under. IMAGE_INSTALL names it "docker", not the recipe's own PN
#   "docker-moby" — docker.inc's own comment ("we want all the docker
#   variant recipes to be installable via 'docker'") plus its
#   `RPROVIDES:${PN} += "docker"` is the intended resolution alias, so this
#   line keeps working even if the layer ever switches to a different
#   docker-ce/docker-moby variant recipe. Pulls docker-cli (RDEPENDS,
#   DOCKER_UNIFIED_PACKAGE defaults "True") and containerd (RDEPENDS
#   "virtual-containerd", resolved via containerd_git.bb's own
#   `RPROVIDES:${PN} = "virtual-containerd"`) transitively — no separate
#   IMAGE_INSTALL line needed for either.
#   REQUIRED_DISTRO_FEATURES gate checked one-hand against docker.inc:
#   `REQUIRED_DISTRO_FEATURES ?= "seccomp ipv6"` — both already present on
#   this distro via oe-core's own DISTRO_FEATURES_DEFAULTS
#   (default-distrovars.inc), never opted out anywhere under
#   meta-duduclaw/meta-yocto (grepped, zero DISTRO_FEATURES_OPTED_OUT hits
#   outside poky-tiny.conf, which this distro does not use) — so the gate
#   is satisfied with NO duduclaw-os.conf change. Docker itself carries no
#   `REQUIRED_DISTRO_FEATURES = "virtualization"` gate (only
#   meta-virtualization's own vdkr/vpdmn/container-image-host multiconfig
#   images do, none of which this appliance builds) — matches the A5 kas.
#   yml comment this wave re-confirmed rather than re-derived from scratch.
#
# runc (meta-virtualization/recipes-containers/runc, PROVIDES "virtual/runc",
#   RPROVIDES "virtual-runc"): listed explicitly, NOT pulled in
#   transitively. docker.inc and containerd_git.bb both gate their OCI-
#   runtime RDEPENDS behind `${VIRTUAL-RUNTIME_container_runtime}`, which
#   only gets a value ("virtual-runc"/"crun") when the distro conf
#   `require`s one of meta-virtualization's own
#   conf/distro/include/meta-virt-container-*.inc snippets
#   (VIRTUAL-RUNTIME_container_runtime ??= "virtual-runc"/"crun") —
#   duduclaw-os.conf requires none of them (grepped, zero hits), so that
#   variable is empty and BOTH docker's and containerd's RDEPENDS on it
#   expand to nothing. Without this line, dockerd installs and can start,
#   but `docker run` fails at the "exec: no OCI runtime" step — a real gap
#   found this wave, not a hypothetical. Wiring
#   VIRTUAL-RUNTIME_container_runtime globally (the meta-virtualization-
#   idiomatic fix) would mean editing duduclaw-os.conf outside this
#   ticket's DISTRO_FEATURES-only conf mandate, so this line is the
#   in-scope fix instead; flagged in the wave report for the integration
#   pass to consider adopting the global variable properly.
#
# docker-compose (meta-virtualization/recipes-containers/docker-compose,
#   PN "docker-compose"): PACKAGECONFIG defaults to "docker-plugin"
#   (docker-compose_git.bb `PACKAGECONFIG ?= "docker-plugin"`), so the
#   binary installs as a `docker compose` CLI plugin
#   (${nonarch_libdir}/docker/cli-plugins/docker-compose), not a standalone
#   `docker-compose` command on $PATH — the modern Compose v2 shape,
#   invoked as `docker compose up`, not `docker-compose up`. No bbappend
#   needed to get compose functionality; B3's CLI wrapper needs to know to
#   shell out to `docker compose`, not the legacy hyphenated binary name.
#
# freerdp3 (meta-openembedded/meta-oe/recipes-support/freerdp,
#   freerdp3_3.24.2.bb): ships `xfreerdp` — the RemoteApp seamless-window
#   X11 client, display prerequisite is CP-1's XWayland (WinApps runs the
#   same shape). PACKAGECONFIG default is
#   `${@bb.utils.filter('DISTRO_FEATURES', 'pam pulseaudio wayland x11', d)}
#   ... gstreamer cups pcsc` — checked one-hand against this distro's own
#   DISTRO_FEATURES: "x11" and "pulseaudio" ship in oe-core's
#   DISTRO_FEATURES_DEFAULTS and are never opted out, "wayland" is
#   explicitly appended by duduclaw-os.conf's Y3-1 block, so PACKAGECONFIG
#   resolves to "pulseaudio wayland x11 gstreamer cups pcsc" — x11 (and
#   therefore xfreerdp) builds WITHOUT any bbappend; only "pam" (not in
#   DISTRO_FEATURES_DEFAULTS, never added) is filtered out, which is fine —
#   RemoteApp doesn't need PAM auth on the client side. No PACKAGES split
#   puts xfreerdp in a separate subpackage (only `${PN}-proxy-plugins`
#   exists as an extra package here) — plain "freerdp3" is the correct
#   IMAGE_INSTALL name, not "freerdp3-tools" (that package name does not
#   exist in this recipe).

IMAGE_INSTALL:append = " duduclaw-compat-runners waydroid docker runc docker-compose freerdp3"
