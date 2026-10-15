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
# --- 2026-10-15: rootless Podman replaced rootful Docker (WP-O2) -----------
# The paragraphs below about docker / runc / docker-compose are kept as
# history; those three packages are no longer installed. The container
# engine is now:
#   podman          rootless, run by duduclaw-podman.service as the gateway
#                   account (uid 1000). PODMAN_FEATURES "docker" (upstream
#                   default) installs the `docker` shim, which is what
#                   compat.d's windows-vm `require_tool = ["docker", ...]`
#                   and the platform's `docker` CLI calls find. Distro
#                   settings (rootless PACKAGECONFIG, root podman.socket not
#                   enabled, container profile) are in duduclaw-os.conf.
#   crun            OCI runtime (meta-virt-container-podman.inc's choice).
#                   CRUN_AS_RUNC installs a `runc` symlink and RCONFLICTS
#                   runc, so runc must not be listed any more.
#   podman-compose  `docker compose` / `podman compose` provider for the
#                   Windows VM runner (docker-compose's default
#                   docker-plugin build needs dockerd).
#   passt           pasta, the rootless network backend (50-duduclaw.conf).
#   duduclaw-podman the API socket/service, store dirs, loopback guard,
#                   root-shell CONTAINER_HOST and module preload list.
#   shadow          newuidmap/newgidmap (useradd.bbclass already makes
#                   useradd packages RDEPEND on shadow; named here because
#                   the setuid allowlist below depends on it).
# Plus two ROOTFS_POSTPROCESS steps at the end of this file: the
# /etc/subuid + /etc/subgid range for the gateway account, and the setuid
# strip with its build-time assertion.
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

IMAGE_INSTALL:append = " duduclaw-compat-runners waydroid freerdp3"
IMAGE_INSTALL:append = " podman crun podman-compose passt duduclaw-podman shadow"

# --- Subordinate ids for the gateway account (2026-10-15, WP-O2) ----------
# Rootless Podman maps container uids/gids 1..65536 onto host ids
# 100000..165535 through newuidmap/newgidmap, which read /etc/subuid and
# /etc/subgid. shadow's do_install only touches both files empty, and on
# the read-only root nothing can add the entry at runtime, so it is written
# into the image here. 65536 ids is what images that run their own non-root
# users (task sandbox `--user uid:gid`) need. 100000 is above every system
# and regular id this image allocates. Not relying on shadow 4.19's
# `useradd --add-subids-for-system`: unverified for this version.
DUDUCLAW_SUBID_USER = "duduclaw"
DUDUCLAW_SUBID_RANGE = "100000:65536"
duduclaw_write_subids () {
    for f in ${IMAGE_ROOTFS}${sysconfdir}/subuid ${IMAGE_ROOTFS}${sysconfdir}/subgid; do
        touch "$f"
        sed -i -e '/^${DUDUCLAW_SUBID_USER}:/d' "$f"
        echo "${DUDUCLAW_SUBID_USER}:${DUDUCLAW_SUBID_RANGE}" >> "$f"
        chmod 0644 "$f"
    done
}
ROOTFS_POSTPROCESS_COMMAND += "duduclaw_write_subids; "

# --- Strip setuid/setgid bits (2026-10-15, WP-O2, threat model H2) --------
# AI employees run as the gateway's uid and can reach the rootless Podman
# API, whose unit cannot have NoNewPrivileges (newuidmap/newgidmap need
# their setuid bit). Through that API a caller can get podman to execute an
# arbitrary host binary inside that unit. Any setuid binary in the image is
# then one exec away from uid 0, so the image ships none except the two
# Podman needs. Candidates this removes: shadow's su/passwd/chfn/chsh/
# newgrp/gpasswd/expiry, busybox.suid's applets, fusermount3 (rootless
# Podman uses kernel overlayfs, not fuse-overlayfs). Effects: root is
# unaffected; no interactive account on this OS needs passwd or su (the
# rescue account logs in directly). Possible casualties to check on the
# first real image (V23 and the extra checks in
# wiki/eval/rootless-verification-2026-10.md): fusermount3 is what lets the
# kiosk user's xdg-document-portal mount its FUSE filesystem, so Flatpak
# apps may lose portal-mediated file access; dbus-daemon-launch-helper (if
# the image uses dbus-daemon) only matters for system services activated
# without a SystemdService= line. Either one may need to go on the
# allowlist after measuring, with the reasoning written here.
#
# Regular files only: setgid DIRECTORIES (group inheritance, not an
# escalation path) are left alone. The same step fails the build if any
# regular file carries file capabilities, or if deferred (first-boot)
# package postinsts are left that could re-add either after this check. The assertion fails the build if a
# setuid/setgid regular file other than the allowlist survives, or if an
# allowlisted binary is missing or lost its setuid bit (without it
# `podman system service` refuses to start: "should have setuid or have
# filecaps setuid"). Runs after duduclaw_write_subids and after the
# read-only-root hook regardless of order, since neither touches modes.
DUDUCLAW_SETUID_ALLOWLIST = "/usr/bin/newuidmap /usr/bin/newgidmap"
duduclaw_strip_setuid () {
    cd ${IMAGE_ROOTFS}
    find . -xdev -type f -perm /6000 | while read -r f; do
        p="${f#.}"
        case " ${DUDUCLAW_SETUID_ALLOWLIST} " in
            *" $p "*) continue ;;
        esac
        chmod u-s,g-s "$f"
        bbnote "duduclaw_strip_setuid: cleared setuid/setgid on $p"
    done
    leftover=$(find . -xdev -type f -perm /6000 | sed -e 's#^\.##' | sort)
    for p in $leftover; do
        case " ${DUDUCLAW_SETUID_ALLOWLIST} " in
            *" $p "*) ;;
            *) bbfatal "duduclaw_strip_setuid: $p still has a setuid/setgid bit after stripping" ;;
        esac
    done
    for p in ${DUDUCLAW_SETUID_ALLOWLIST}; do
        [ -f ".$p" ] || bbfatal "duduclaw_strip_setuid: $p is missing (rootless Podman needs it setuid; is shadow installed?)"
        [ -u ".$p" ] || bbfatal "duduclaw_strip_setuid: $p is not setuid (rootless Podman refuses to start without it)"
    done

    cd - >/dev/null
}
ROOTFS_POSTPROCESS_COMMAND += "duduclaw_strip_setuid; "

# File capabilities are the other way an exec gains privilege (the
# security.capability xattr; a cap_setuid+ep binary is as good as setuid
# root). newuidmap/newgidmap stay setuid, not fcaps, so NO regular file may
# carry file capabilities. A python function, not shell: do_rootfs is a
# fakeroot task, so this runs in bitbake's pseudo-wrapped worker and
# os.getxattr sees the xattrs packages set (and no heredoc trips bitbake's
# shell parser). Deferred package postinsts (pkg_postinst_ontarget, run by
# run-postinsts on first boot) would run after both checks and could add
# setuid bits or capabilities back, so none may be left either. A hit fails
# the build; a genuinely needed exception goes in here with its reasoning,
# never by loosening the check.
python duduclaw_check_filecaps () {
    import os
    root = d.getVar('IMAGE_ROOTFS')
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        for name in filenames:
            path = os.path.join(dirpath, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                os.getxattr(path, 'security.capability', follow_symlinks=False)
            except OSError:
                continue
            found.append(path[len(root):])
    if found:
        bb.fatal('duduclaw_check_filecaps: regular files with file capabilities: %s' % ' '.join(sorted(found)))
    etc = root + d.getVar('sysconfdir')
    for pm in ('rpm-postinsts', 'ipk-postinsts', 'deb-postinsts'):
        pdir = os.path.join(etc, pm)
        if os.path.isdir(pdir) and os.listdir(pdir):
            bb.fatal('duduclaw_check_filecaps: deferred postinsts left in %s: %s' % (pdir[len(root):], ' '.join(sorted(os.listdir(pdir)))))
}
ROOTFS_POSTPROCESS_COMMAND += "duduclaw_check_filecaps; "
